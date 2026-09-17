#ifndef WATTLITE_SMC_H
#define WATTLITE_SMC_H
#include <stdint.h>
uint32_t smc_open(void);
void smc_close(uint32_t connection);
int smc_read(uint32_t connection, const char *key, double *value);
int smc_key_at(uint32_t connection, uint32_t index, char key[5]);
#endif
