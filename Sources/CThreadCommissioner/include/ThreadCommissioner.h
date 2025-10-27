//
//  ThreadCommissioner.h
//  ThreadCommissioner
//
//  Umbrella header for Thread Commissioner package
//

#ifndef ThreadCommissioner_h
#define ThreadCommissioner_h

// Import from mbedTLS framework
#import <mbedtls/ssl.h>
#import <mbedtls/net_sockets.h>
#import <mbedtls/entropy.h>
#import <mbedtls/ctr_drbg.h>
#import <mbedtls/error.h>
#import <mbedtls/debug.h>
#import <mbedtls/timing.h>
#import <mbedtls/ssl_ciphersuites.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// EC-JPAKE password function declaration
int mbedtls_ssl_set_hs_ecjpake_password(mbedtls_ssl_context *ssl,
                                        const unsigned char *pw,
                                        size_t pw_len);

#ifdef __cplusplus
}
#endif

#endif /* ThreadCommissioner_h */
