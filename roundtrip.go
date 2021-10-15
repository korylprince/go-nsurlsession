package roundtrip

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"strings"
	"unsafe"
)

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -lobjc -framework Foundation -framework Security

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "http.h"
*/
import "C"

type HTTPError struct {
	Code        int
	Description string
}

func (e *HTTPError) Error() string {
	return fmt.Sprintf("HTTP Error (%d): %s", e.Code, e.Description)
}

type FoundationRoundTripper struct {
	IdentitySubjectName string
}

func (f *FoundationRoundTripper) RoundTrip(r *http.Request) (*http.Response, error) {
	// marshal identity subject name if it exists
	var subject *C.char
	if f.IdentitySubjectName != "" {
		subject = C.CString(f.IdentitySubjectName)
		defer C.free(unsafe.Pointer(subject))
	}

	// marshal url and method
	url := C.CString(r.URL.String())
	defer C.free(unsafe.Pointer(url))
	method := C.CString(r.Method)
	defer C.free(unsafe.Pointer(method))

	// marshal headers
	var headers []C.struct_http_header
	for k := range r.Header {
		key := C.CString(k)
		defer C.free(unsafe.Pointer(key))
		val := C.CString(strings.Join(r.Header.Values(k), ","))
		defer C.free(unsafe.Pointer(val))
		headers = append(headers, C.struct_http_header{key: key, val: val})
	}

	var headerPtr *C.struct_http_header
	if len(headers) > 0 {
		headerPtr = &headers[0]
	}

	// marshal body
	buf := new(bytes.Buffer)

	if r.Body != nil {
		if _, err := buf.ReadFrom(r.Body); err != nil {
			return nil, fmt.Errorf("could not buffer body: %w", err)
		}
		r.Body.Close()
	}

	bodyPtr := C.CBytes(buf.Bytes())
	defer C.free(unsafe.Pointer(bodyPtr))

	// marshal http_request
	req := (*C.struct_http_request)(C.malloc(C.sizeof_struct_http_request))
	defer C.free(unsafe.Pointer(req))
	req.url = url
	req.method = method
	req.headers = headerPtr
	req.headers_len = C.NSUInteger(len(headers))
	req.body = bodyPtr
	req.body_len = C.NSUInteger(buf.Len())

	// do request
	resp := C.RoundTrip(req, subject)
	defer C.FreeHTTPResponse(resp)

	// parse error
	if resp.error != nil {
		return nil, &HTTPError{
			Code:        int(resp.error.code),
			Description: C.GoString(resp.error.msg),
		}
	}

	// parse protocol
	var (
		p    string
		pmaj int
		pmin int
	)
	if resp.proto != nil {
		proto := C.GoString(resp.proto)
		if proto == "h2" || proto == "h2c" {
			p = "HTTP/2.0"
			pmaj = 2
			pmin = 0
		} else if proto == "http/1.1" {
			p = "HTTP/1.1"
			pmaj = 1
			pmin = 1
		}
	}

	// parse headers
	respHeaders := make(http.Header)
	if resp.headers != nil {
		cHeaders := (*[1 << 30]C.struct_http_header)(unsafe.Pointer(resp.headers))[:resp.headers_len:resp.headers_len]
		for _, h := range cHeaders {
			k := C.GoString(h.key)
			v := C.GoString(h.val)
			respHeaders.Set(k, v)
		}
	}

	body := bytes.NewBuffer(C.GoBytes(resp.body, C.int(resp.body_len)))

	return &http.Response{
		Proto:         p,
		ProtoMajor:    pmaj,
		ProtoMinor:    pmin,
		Status:        http.StatusText(int(resp.statusCode)),
		StatusCode:    int(resp.statusCode),
		Header:        respHeaders,
		Body:          io.NopCloser(body),
		ContentLength: int64(body.Len()),
		Request:       r,
	}, nil
}
