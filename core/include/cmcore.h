#ifndef CMCORE_H
#define CMCORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cm_service cm_service;

uint32_t cm_service_version(void);
cm_service *cm_service_create(void);
void cm_service_destroy(cm_service *service);
int32_t cm_service_submit(cm_service *service, const char *intent_json);
void cm_service_pump(cm_service *service, int64_t now_unix_s);
const char *cm_service_project(cm_service *service);
const char *cm_service_provenance(void);
int32_t cm_service_keychain_probe(cm_service *service, char *out, size_t cap);

#ifdef __cplusplus
}
#endif

#endif
