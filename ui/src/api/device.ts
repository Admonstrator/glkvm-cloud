/*
 * @Author: shufei.han
 * @Date: 2025-06-11 11:48:02
 * @LastEditors: LPY
 * @LastEditTime: 2025-08-26 16:07:23
 * @FilePath: \glkvm-cloud\web-ui\src\api\device.ts
 * @Description: 设备相关API
 */
import { ExecuteCommandParams, type DeviceInfo } from '@/models/device'
import { httpService } from './request'

/** 获取设备列表 */
export const getDeviceListApi = () => {
    return httpService.get<DeviceInfo[]>('/devs')
}

/** 获取添加设备脚本 */
export const getAddDeviceScriptInfoApi = () => {
    return httpService.get('/get/scriptInfo')
}

/** 执行命令 */
export const reqExecuteCommand = (data: ExecuteCommandParams) => {
    return httpService.post(`/cmd/${data.id}?group=${data.group}&wait=${data.wait}`, data)
}