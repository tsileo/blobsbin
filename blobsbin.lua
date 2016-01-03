local log = require('logger')

local req = require('request')
local resp = require('response')

local kvs = require('kvstore')
local bs = require('blobstore')

local bewit = require('bewit')
local tpl = require('template')

local hightlightCss = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/9.0.0/styles/default.min.css"
local tplSnippet = [[<div style="max-width:960px;margin:20px auto;padding:0 20px;">
<h1>{{ .Paste.filename }}</h1>
<pre><code>{{ .Paste.content }}</pre></code>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/9.0.0/highlight.min.js"></script>
<script>hljs.initHighlightingOnLoad();</script>
<p style="color:#aaa;font-size:0.9em;margin-top:20px;">Powered by 
<a href="https://github.com/tsileo/blobsbin" style="text-decoration:none;color:#333;">BlobBin</a> and 
<a href="https://github.com/tsileo/blobstash" style="text-decoration:none;color:#333;">BlobStash</a>.</p>
</div>]]

if req.method() == 'GET' then
  if req.queryarg('key') ~= "" then
    -- #####################
    -- Private paste display
    -- #####################
    if not req.authorized() then
      resp.authenticate('Pastes dashboard')
      resp.error(401)
      do return end
    end
    local kv = kvs.getjson(req.queryarg('key'), -1)
    local paste = kv.value
    paste.content = bs.get(paste.content_ref)
    tpl.addcss(hightlightCss)
    tpl.settitle("Paste: " .. paste.filename)
    tpl.setctx{Paste = paste}
    resp.write(tpl.render(tplSnippet))
    do return end
  elseif req.queryarg('id') == "" then
    -- ######################
    -- Private pastes listing
    -- ######################
    if not req.authorized() then
      resp.authenticate('Pastes dashboard')
      resp.error(401)
      do return end
    end
    local pastes = kvs.keysjson("paste:", "paste:\\xff", 100)
    for i = 1, #pastes do
      pastes[i].value.bewit = bewit.new(url(string.format('/app/%v?id=%v', appID, pastes[i].value.id)))
    end
    tpl.settitle("Pastes")
    tpl.setctx{Pastes = pastes}
    resp.write(tpl.render(string.format([[<div style="max-width:960px;margin:20px auto;padding:0 20px;">
    <h1>Pastes</h1>
    <ul>
    {{ range .Pastes }}
      <li><a href="?key={{ .key }}">{{ .value.filename }}</a> | <a href="%v?id={{ .value.id }}&bewit={{ .value.bewit }}">share</a></li>
    {{ end }}
    </ul>
    </div>]], url('/app/'..appID))))
    do return end
  end
  if req.queryarg('id') ~= "" and bewit.check() == "" then
    -- ################
    -- Public paste get
    -- ################
    -- Retrieve the paste
    local pastekey = string.format('paste:%v', req.queryarg('id'))
    local kv = kvs.getjson(pastekey, -1)
    local paste = kv.value
    paste.content = bs.get(paste.content_ref)

    -- Log the access
    log.info(string.format("Paste %s/%s has been accessed by %s", paste.filename, pastekey, req.remoteaddr()))

    -- Build the HTML response
    tpl.settitle(string.format("Paste: %v", paste.filename))
    tpl.addcss(hightlightCss)
    tpl.setctx{Paste = paste}
    resp.write(tpl.render(tplSnippet))
  end
  if bewit.check() ~= "" then
    log.info(string.format('Unauthorized access from %v with error=%q', req.remoteaddr(), bewit.check()))
    resp.error(401)
  end
elseif req.method() == 'POST' then
  -- #######################
  -- Handle the paste upload
  -- #######################
  if not req.authorized() then
    resp.error(401)
    do return end
  else
    -- Parse the uploded files
    local form, files = req.upload()

    -- Store the file content in a blob
    local contentref = blake2b(files.file.content)
    bs.put(contentref, files.file.content)

    -- Create the paste object
    local pasteid = hexid()
    local paste = {id = pasteid, filename = files.file.filename, content_ref = contentref}
    local pastekey = string.format('paste:%s', pasteid)
    -- Save it in the kvstore
    kvs.putjson(pastekey, paste, -1)

    local url = url('/app/hello?id=' .. pasteid)
    local token = bewit.new(url)
    url = url .. '&bewit=' .. token

    -- Returns a nice JSON response
    resp.jsonify{paste = paste, id = pasteid, url = url}
  end
end
