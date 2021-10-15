#import <string.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "http.h"

NSURLCredential *URLCredentialBySubject(NSString *subjectName) {
	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassIdentity,
		(__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
		(__bridge id)kSecMatchSubjectWholeString: subjectName,
	    (__bridge id)kSecReturnRef: @TRUE,
	};
	SecIdentityRef ref;
	OSStatus code = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)(&ref));
	if (code != errSecSuccess) {
		// FIXME: return error here somehow
		NSLog(@"%@", SecCopyErrorMessageString(code, nil));
		return nil;
	}

	NSURLCredential *cred = [NSURLCredential credentialWithIdentity:ref certificates:nil persistence:NSURLCredentialPersistenceNone];
	return cred;
}

NSMutableURLRequest *NewNSURLRequest(http_request *r) {
	NSURL *url = [NSURL URLWithString: [NSString stringWithCString:r->url encoding:NSUTF8StringEncoding]];
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: url];
	req.HTTPMethod = [NSString stringWithCString:r->method encoding:NSUTF8StringEncoding];
	req.HTTPBody = [NSData dataWithBytes:r->body length:r->body_len];
	for (NSUInteger i = 0; i < r->headers_len; i++) {
		NSString *key = [NSString stringWithCString:r->headers[i].key encoding:NSUTF8StringEncoding];
		NSString *val = [NSString stringWithCString:r->headers[i].val encoding:NSUTF8StringEncoding];
		[req setValue:val forHTTPHeaderField:key];
	}
	return req;
}

@implementation SessionDelegate {
	NSURLCredential *cred;
	http_response *resp;
	dispatch_semaphore_t semaphore;
}

- (void)setCredential: (NSURLCredential *)c {
	cred = c;
}

- (void)setResponse: (http_response *)r {
	resp = r;
}

- (void)setSemaphore: (dispatch_semaphore_t)s {
	semaphore = s;
}

- (void)URLSession: (NSURLSession *)session task:(NSURLSessionTask *)task didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics {
	for (NSUInteger idx = 0; idx < metrics.transactionMetrics.count; idx++) {
		if (metrics.transactionMetrics[idx].networkProtocolName != nil) {
			char *proto = (char *)metrics.transactionMetrics[idx].networkProtocolName.UTF8String;
			char *p = calloc(strlen(proto), 1);
			strncpy(p, proto, strlen(proto));
			resp->proto = p;
		}
	}
	dispatch_semaphore_signal(semaphore);
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
	if (challenge.protectionSpace.authenticationMethod != NSURLAuthenticationMethodClientCertificate) {
		completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
		return;
	}
	// good luck with this actually working...
	completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
}
@end

http_response *DoRequest(NSMutableURLRequest *req, NSURLCredential *cred) {
	SessionDelegate *delegate = [[SessionDelegate alloc] init];
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
	config.TLSMaximumSupportedProtocolVersion = tls_protocol_version_TLSv13;
	NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:nil];

	[delegate setCredential:cred];
	http_response *r = calloc(1, sizeof(struct http_response));
	[delegate setResponse:r];
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	[delegate setSemaphore:semaphore];

	NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
		if (data != nil) {
			void *respData = malloc(data.length);
			[data getBytes:respData length:data.length];
			r->body = respData;
			r->body_len = data.length;
		}

		if (resp != nil) {
			NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*)resp;
			r->statusCode = httpResp.statusCode;
			r->headers = malloc(httpResp.allHeaderFields.count * sizeof(struct http_header));
			r->headers_len = httpResp.allHeaderFields.count;
			__block int idx = 0;
			[httpResp.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id nskey, id nsval, BOOL *stop) {
				char *key = (char *)(((NSString *)nskey).UTF8String);
				char *k = calloc(strlen(key), 1);
				strncpy(k, key, strlen(key));
				r->headers[idx].key = k;

				char *val = (char *)(((NSString *)nsval).UTF8String);
				char *v = calloc(strlen(val), 1);
				strncpy(v, val, strlen(val));
				r->headers[idx].val = v;
				idx++;
			}];
		}

		if (error != nil) {
			http_error *err = malloc(sizeof(http_error));
			err->code = error.code;
			char *msg = (char *)[error localizedDescription].UTF8String;
			char *m = calloc(strlen(msg), 1);
			strncpy(m, msg, strlen(msg));
			err->msg = m;
			r->error = err;
		}
		dispatch_semaphore_signal(semaphore);
	}];

	[task resume];

	// wait for completionHandler and delegate to write data before returning
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

	return r;
}

http_response *RoundTrip(http_request *r, char *subjectName) {
	NSString *subject = [NSString stringWithCString:subjectName encoding:NSUTF8StringEncoding];
	NSURLCredential *cred = URLCredentialBySubject(subject);
	NSMutableURLRequest *req = NewNSURLRequest(r);
	return DoRequest(req, cred);
}

void FreeHTTPResponse(http_response *r) {
	if (r != nil) {
		if (r->proto != nil) {
			free(r->proto);
		}
		if (r->headers != nil) {
			for (NSUInteger idx = 0; idx < r->headers_len; idx++) {
				free(r->headers[idx].key);
				free(r->headers[idx].val);
			}
			free(r->headers);
		}

		if (r->body != nil) {
			free(r->body);
		}

		if (r->error != nil) {
			if (r->error->msg != nil) {
				free(r->error->msg);
			}
			free(r->error);
		}
		free(r);
	}
}
