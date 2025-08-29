/*
 * @Author: LPY
 * @Date: 2025-05-30 09:24:47
 * @LastEditors: LPY
 * @LastEditTime: 2025-06-09 16:49:00
 * @FilePath: /kvm-cloud-frontend/src/models/setting.ts
 * @Description: 设置相关类型声明
 */

import { Languages, SelectOptions } from '@gl/main'

/** 语言对应的label映射 */
export const languageLabelMap = new Map<Languages, string>([
    [Languages.ZH, '中文'],
    [Languages.EN, 'English'],
])

/** 语言选择options */
export const languageOptions = Object.values(Languages).map(lang => new SelectOptions(lang, languageLabelMap.get(lang)))

export interface Theme {
    attribute: string,
    content: any,
}