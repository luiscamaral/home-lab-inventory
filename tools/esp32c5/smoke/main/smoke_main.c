/*
 * smoke_main.c — ESP32-C5 HIL smoke test
 *
 * Prints a known banner over UART then loops with a heartbeat.
 * Used to validate: toolchain, flash path, and serial capture.
 *
 * Expected serial output:
 *   ESP32C5-SMOKE-BANNER-OK
 *   Heartbeat: 0
 *   Heartbeat: 1
 *   ...
 */

#include <stdio.h>
#include <inttypes.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_chip_info.h"

static const char *TAG = "smoke";

void app_main(void)
{
    esp_chip_info_t chip;
    esp_chip_info(&chip);

    /* Known banner — hil-tester asserts this exact string */
    printf("\n");
    printf("ESP32C5-SMOKE-BANNER-OK\n");
    printf("Chip: model=%d cores=%d features=0x%08" PRIx32 " revision=%d\n",
           chip.model, chip.cores, chip.features, chip.revision);
    fflush(stdout);

    ESP_LOGI(TAG, "Smoke test running on esp32c5");
    ESP_LOGI(TAG, "IDF version: %s", IDF_VER);

    uint32_t count = 0;
    while (1) {
        ESP_LOGI(TAG, "Heartbeat: %" PRIu32, count++);
        vTaskDelay(pdMS_TO_TICKS(2000));
    }
}
