#import <Foundation/Foundation.h>

static int failures;
static void expect(BOOL condition, NSString *message)
{
    if (!condition) { NSLog(@"FAIL: %@", message); failures++; }
}

/* Independent input using the keys published by swift-corelibs-foundation's
 * FoundationNetworking/URLResponse.swift, including a length above 32 bits. */
@interface ResponseFixture : NSCoder
@property (nonatomic, strong) NSDictionary *values;
@end
@implementation ResponseFixture
- (BOOL)allowsKeyedCoding { return YES; }
- (id)decodeObjectForKey:(NSString *)key { return [_values objectForKey:key]; }
- (id)decodeObjectOfClass:(Class)cls forKey:(NSString *)key
{
    id value = [self decodeObjectForKey:key];
    return [value isKindOfClass:cls] ? value : nil;
}
- (id)decodeObjectOfClasses:(NSSet *)classes forKey:(NSString *)key
{
    for (Class cls in classes) {
        id value = [self decodeObjectOfClass:cls forKey:key];
        if (value != nil) return value;
    }
    return nil;
}
- (int64_t)decodeInt64ForKey:(NSString *)key { return [[_values objectForKey:key] longLongValue]; }
- (NSInteger)decodeIntegerForKey:(NSString *)key { return [[_values objectForKey:key] integerValue]; }
@end

static NSURLResponse *roundTrip(NSURLResponse *response)
{
    return [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:response]];
}

static void checkHTTP(NSHTTPURLResponse *response, NSURL *url)
{
    expect([response statusCode] == 206, @"decoded status");
    expect([[response URL] isEqual:url], @"decoded HTTP URL");
    expect([[response MIMEType] isEqualToString:@"image/png"], @"decoded HTTP MIME type");
    expect([response expectedContentLength] == 42, @"decoded HTTP length");
    expect([[[response allHeaderFields] objectForKey:@"X-Probe"] isEqualToString:@"coding"], @"decoded header");
    NSData *data = [@"icon" dataUsingEncoding:NSUTF8StringEncoding];
    NSCachedURLResponse *cached = [[NSCachedURLResponse alloc] initWithResponse:response data:data];
    expect([[cached response] URL] != nil, @"decoded response can enter URL cache");
    expect([[cached data] isEqualToData:data], @"cached data");
}

int main(void)
{
    @autoreleasepool {
        NSURL *url = [NSURL URLWithString:@"https://example.test/icon.png"];
        ResponseFixture *fixture = [[ResponseFixture alloc] init];
        fixture.values = @{
            @"NS.url": url, @"NS.statusCode": @206,
            @"NS.allHeaderFields": @{ @"Content-Type": @"image/png", @"Content-Length": @"42", @"X-Probe": @"coding" }
        };
        NSHTTPURLResponse *http = [[NSHTTPURLResponse alloc] initWithCoder:fixture];
        checkHTTP(http, url);
        checkHTTP((NSHTTPURLResponse *)roundTrip(http), url);

        fixture.values = @{
            @"NS.url": url, @"NS.mimeType": @"text/plain",
            @"NS.expectedContentLength": @5000000000LL, @"NS.textEncodingName": @"utf-8"
        };
        NSURLResponse *base = [[NSURLResponse alloc] initWithCoder:fixture];
        for (NSURLResponse *response in @[base, roundTrip(base)]) {
            expect([[response URL] isEqual:url], @"decoded base URL");
            expect([[response MIMEType] isEqualToString:@"text/plain"], @"decoded base MIME type");
            expect([response expectedContentLength] == 5000000000LL, @"64-bit archived length");
            expect([[response textEncodingName] isEqualToString:@"utf-8"], @"decoded encoding");
        }
        fixture.values = @{ @"NS.url": url, @"NS.expectedContentLength": @(-1) };
        base = [[NSURLResponse alloc] initWithCoder:fixture];
        expect([base expectedContentLength] == NSURLResponseUnknownLength, @"unknown archived length");
        expect([base MIMEType] == nil && [base textEncodingName] == nil, @"optional archived metadata");
        fixture.values = @{};
        expect([[NSURLResponse alloc] initWithCoder:fixture] == nil, @"missing URL rejects base response");
        expect([[NSHTTPURLResponse alloc] initWithCoder:fixture] == nil, @"missing URL rejects HTTP response");
        expect([[NSCachedURLResponse alloc] initWithResponse:nil data:[NSData data]] == nil, @"rejected decoded response cannot enter cache");
        expect([[NSCachedURLResponse alloc] initWithResponse:http data:nil] == nil, @"missing cached data rejects initialization");
    }
    if (!failures) NSLog(@"PASS: nsurlresponse-coding");
    return failures ? 1 : 0;
}
