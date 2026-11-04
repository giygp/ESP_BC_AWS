/*
 * @Author: zhong chenjian zhongcj@softide.cn
 * @Date: 2021-10-08 14:03:40
 * @LastEditors: zhong chenjian zhongcj@softide.cn
 * @LastEditTime: 2022-06-27 15:56:57
 * @FilePath: /smart-air-bed-board-program/main/smart_air_bed_main.c
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
#include <stdio.h>
#include "sdkconfig.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_spi_flash.h"
#include "nvs_flash.h"
#include "use_adc.h"
#include "use_wifi.h"
#include "ble_server.h"
#include "use_pwm.h"
#include "use_ota.h"
#include "common.h"
#include "app_control.h"
#include "use_uart.h"
#include "cJSON.h"
#include "esp_heap_caps.h"
// #include "esp_log.h"

/* cJSON 节点都很小，默认会进内部 RAM。报告一包 200 个数就会拆碎 TLS 需要的连续空间。 */
static void *cjson_malloc_spiram(size_t sz)
{
    void *p = heap_caps_malloc(sz, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (p == NULL) {
        p = heap_caps_malloc(sz, MALLOC_CAP_8BIT);
    }
    return p;
}

static void cjson_free_any(void *p)
{
    heap_caps_free(p);
}

void app_main(void)
{
  cJSON_Hooks hooks = {
      .malloc_fn = cjson_malloc_spiram,
      .free_fn = cjson_free_any,
  };
  cJSON_InitHooks(&hooks);

  //初始化 NVS
  vTaskDelay(500 / portTICK_PERIOD_MS);
	esp_err_t ret = nvs_flash_init();
	if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND)
	{
		ESP_ERROR_CHECK(nvs_flash_erase());
		ret = nvs_flash_init();
	}
  device_init();

  // config_store();               //默认配置 需单独配置
  // read_config();                //读取用户配置
  /* 震动马达相关
    //Key_Gpio_init();
    //pwm_init();                   //PWM初始化
  */
  // initialize_adc();             //气压采集系统

  initialize_ble_server();      //蓝牙初始化
  initialize_wifi();            //wifi初始化
  mfp_gpio_config();
  app_control_server();           //app通信控制系统

}
