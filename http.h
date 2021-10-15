#include <Foundation/Foundation.h>

typedef struct http_header {
    char *key;
    char *val;
} http_header;

typedef struct http_request {
    char *url;
    char *method;
    http_header *headers;
    NSUInteger headers_len;
    void *body;
    NSUInteger body_len;
} http_request;

typedef struct http_error {
    NSInteger code;
    char *msg;
} http_error;

typedef struct http_response {
    NSInteger statusCode;
    char *proto;
    http_header *headers;
    NSUInteger headers_len;
    void *body;
    NSUInteger body_len;
    http_error *error;
} http_response;

NSURLCredential *URLCredentialBySubject(NSString *cn);

NSMutableURLRequest *NewNSURLRequest(http_request *r);

@interface SessionDelegate:NSObject <NSURLSessionDelegate>
- (void)setCredential: (NSURLCredential *)c;
- (void)setResponse: (http_response *)r;
- (void)setSemaphore: (dispatch_semaphore_t)s;
- (void)URLSession: (NSURLSession *)session
    task:(NSURLSessionTask *)task
    didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics;
- (void)URLSession: (NSURLSession *)session 
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge 
    completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler;
@end

http_response *DoRequest(NSMutableURLRequest *req, NSURLCredential *cred);

http_response *RoundTrip(http_request *req, char *subjectName);

void FreeHTTPResponse(http_response *r);
