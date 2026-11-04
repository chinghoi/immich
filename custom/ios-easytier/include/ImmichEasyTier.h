#pragma once
#include <stdint.h>
int32_t immich_et_start(const char *options);
int32_t immich_et_stop(void);
char *immich_et_status(const char *target);
void immich_et_free(char *value);
