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

local function showPaste(paste)
  tpl.addcss(hightlightCss)
  tpl.settitle("BlobsBin: " .. paste.filename)
  tpl.setctx{Paste = paste}
  resp.write(tpl.render(tplSnippet))
end

if req.method() == 'GET' then
  if req.queryarg('show') ~= "" then
    -- #####################
    -- Private paste display
    -- #####################
    if not req.authorized() then
      resp.authenticate('Pastes dashboard')
      resp.error(401)
      do return end
    end
    local kv = kvs.getjson(req.queryarg('show'), -1)
    local paste = kv.value
    paste.content = bs.get(paste.content_ref)
    showPaste(paste)
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
    tpl.settitle("BlobsBin: Pastes")
    tpl.setctx{Pastes = pastes}
    resp.write(tpl.render(string.format([[<div style="max-width:960px;margin:20px auto;padding:0 20px;">
    <h1>Pastes</h1>
    <p style="color:#aaa;">Semi-private links have a one hour validty.</p>
    <ul>
    {{ range .Pastes }}
      <li><a href="?show={{ .key }}">{{ .value.filename }}</a> <a style="color:#aaa;text-decoration:none;" {{ if .value.public }}href="%v?id={{ .value.id }}">(public)</a>
      {{ else }}href="%v?id={{ .value.id }}&bewit={{ .value.bewit }}">(semi-private)</a>{{ end }}</li>
    {{ end }}
    </ul>
    </div>]], url('/app/'..appID))))
    do return end
  elseif req.queryarg('id') ~= "" then
    -- ################
    -- Public paste get
    -- ################
    -- Retrieve the paste
    local pastekey = string.format('paste:%v', req.queryarg('id'))
    local kv = kvs.getjson(pastekey, -1)
    local paste = kv.value
    paste.content = bs.get(paste.content_ref)

    if not paste.public and bewit.check() ~= "" then
      log.info(string.format('Unauthorized access from %v with error=%q', req.remoteaddr(), bewit.check()))
      resp.error(401)
      do return end
    end

    -- Log the access
    log.info(string.format("Paste %s/%s has been accessed by %s", paste.filename, pastekey, req.remoteaddr()))

    -- Build the HTML response
    showPaste(paste)
    do return end
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
    local paste = {id = pasteid, filename = files.file.filename, content_ref = contentref, public = false}
    if form.public == "1" then
      paste.public = true
    end
    local pastekey = string.format('paste:%s', pasteid)
    -- Save it in the kvstore
    kvs.putjson(pastekey, paste, -1)

    local url = url('/app/hello?id=' .. pasteid)
    -- Only generate a single-auth link if the paste isn't public
    if not paste.public then
      local token = bewit.new(url)
      url = url .. '&bewit=' .. token
    end

    log.info(string.format('Paste [filename=%q, id=%q, public=%s] created', paste.filename, pasteid, paste.public))

    -- Returns a nice JSON response
    resp.jsonify{paste = paste, id = pasteid, url = url}
  end
end
