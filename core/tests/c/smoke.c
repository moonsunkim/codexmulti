#include "cmcore.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* Prints only the contract's non-secret projection summary. */
static int has(const char *json, const char *text) { return strstr(json, text) != NULL; }
int main(void) {
    if (cm_service_version() != 1) return 10;
    cm_service *service = cm_service_create();
    if (!service) return 11;
    if (cm_service_submit(service, "{\"intent\":\"refresh_all\"}") != 0) return 12;
    cm_service_pump(service, 1784948400);
    const char *json = cm_service_project(service);
    const char *generation = strstr(json, "\"generation\":");
    if (!generation) return 13;
    if (!has(json, "in progress") && !has(json, "does not allow") && !has(json, "no application service")) return 14;
    printf("generation=%llu runtime.started=%s capabilities.connected=%s refresh=%s accounts=%s reset=%s proxy_control=%s\n", strtoull(generation + 13, NULL, 10), has(json, "\"runtime\":{\"started\":true") ? "true" : "false", has(json, "\"connected\":true") ? "true" : "false", has(json, "\"refresh\":true") ? "true" : "false", has(json, "\"accounts\":true") ? "true" : "false", has(json, "\"reset\":true") ? "true" : "false", has(json, "\"proxy_control\":true") ? "true" : "false");
    cm_service_destroy(service);
    return 0;
}
