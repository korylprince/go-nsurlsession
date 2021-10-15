# About

This is an implementation of http.RoundTripper that uses Apple's NSURLSession instead of http.Transport. Pretty much all of the useful fields in http.Request and http.Response are converted back and forth. The request and response body are buffered and passed as a []byte, so streaming data won't work well.

The original purpose in building this library was to use client certificates from the keychain with [URLSession:didReceiveChallenge:completionHandler:](https://developer.apple.com/documentation/foundation/nsurlsessiondelegate/1409308-urlsession) to use an MDM identity certificate as a TLS client certificate. However this doesn't seem to work on Big Sur. I leave this here so the next poor soul who tries to do this will at least have something to build on.

**To be clear:** I wouldn't recommend using this in production. I make no promises that I haven't introduced some terrible bug in the Objective-C code.

# Usage

```go
client := &http.Client{Transport: &FoundationRoundTripper{}}
// do things with client
```
