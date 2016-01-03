# BlobsBin

BlobsBin is a paste service for privately sharing snippets.

This is a [BlobStash](https://github.com/tsileo/blobstash) app written in Lua.

## Feature

- Public pastes support
- Semi-private sharing support with [Hawk bewit authentication](https://github.com/hueniverse/hawk#single-uri-authorization)
- All your data stored in BlobStash

## Installation

```shell
$ blobstash-app -public register blobsbin blobsbin.lua
```

BlobsBin will be available at `/app/blobsbin`.

## Usage

### List/show pastes

Go to `/app/blobsbin` and login with your API key as password to get a basic web interface for managing pastes.

### Create a new paste

Create a new paste using [HTTPie](https://github.zohttps://github.com/jkbrzt/httpie/):

```shell
$ http -f --auth :APIKEY POST http://localhost:8050/app/blobsbin file@/path/to/file
```

Or using Curl:

```shell
$ curl -u :APIEKY -F "file=@/path/to/file" http://localhost:8050/app/blobsbin
```

It will returns a JSON payload with the `url` key (the link will be valid for one hour).

### Upload a public paste

Just add a `public=1` field to the POST request:

```shell
$ http -f --auth :APIKEY POST http://localhost:8050/app/blobsbin public=1 file@/path/to/file
```
