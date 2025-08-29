/*
 * @Author: LPY
 * @Date: 2025-05-30 09:54:21
 * @LastEditors: LPY
 * @LastEditTime: 2025-08-26 14:53:11
 * @FilePath: \glkvm-cloud\web-ui\src\router\index.ts
 * @Description: 路由文件
 */
import { createRouter, createWebHashHistory, RouterView } from 'vue-router'
import whiteList from './whiteList'
import layoutPage from '@/views/layout/layoutPage.vue'
import { useUserStore } from '@/stores/modules/user'
import { BreadCrumbItem } from '@/hooks/useBreadcrumb'

declare module 'vue-router' {
    interface RouteMeta {
        /** 面包屑 */
        breadcrumbs?: BreadCrumbItem[]
        /** 是否展示到侧边栏 */
        menu?: boolean
        /** 联动父元素的path(例如添加设备页，若不展示在侧边栏内，但是在添加设备页，需要选中左侧的menu，则传入需要选中menu的path)，仅支持设置顶级path且menu不能为true */
        linkageParentLevelPath?: string
        /** 如果需要展示到侧边栏，则title和icon必填 */ 
        title?: string
        /** 如果需要展示到侧边栏，则title和icon必填 */ 
        icon?: string
        /** 不需要在路由表的meta中添加， 仅用于侧边栏判断*/
        whetherToExpandChildElements?: boolean
    }
}

/** 路由文件 */
const router = createRouter({
    history: createWebHashHistory(),
    routes: [
        /** 登录 */
        {
            path: '/login',
            component: () => import('@/views/login/loginPage.vue'),
            name: 'login',
        },
        /** SSH */
        {
            path: '/rtty/:devid',
            component: () => import('@/views/device/rttyPage.vue'),
            name: 'rtty',
            props: true,
        },
        /** 非白名单页 */
        {
            path: '/',
            component: layoutPage,
            name: 'layout',
            redirect: '/device',
            children: [
                /** 设备列表 */
                {
                    path: '/device',
                    component: () => import('@/views/device/devicePage.vue'),
                    name: 'device',
                    meta: {
                        menu: true,
                        title: 'device.devices',
                        icon: 'gl-icon-device',
                    },
                },
                
                /** 测试页 */
                {
                    path: '/test',
                    component: RouterView,
                    name: 'test',
                    meta: {
                        title: 'test',
                        icon: 'gl-icon-setup',
                    },
                    redirect: '/test/child1',
                    children: [
                        {
                            path: '/test/child1',
                            component: () => import('@/views/test/testPage.vue'),
                            name: 'testChild1',
                            meta: {
                                title: 'test child1',
                                icon: 'gl-icon-circle-check-solid',
                            },
                        },
                        {
                            path: '/test/child2',
                            component: () => import('@/views/test/testPage.vue'),
                            name: 'testChild2',
                            meta: {
                                title: 'test child2',
                                icon: 'gl-icon-circle-xmark-solid',
                            },
                        },
                    ],
                },
            ],
        },
        /** 404页面 */
        {
            path: '/error',
            component: () => import('@/views/error/errorPage.vue'),
            name: 'error',
        },
        {
            path: '/:pathMatch(.*)*',
            redirect: '/error',
        },
    ],
})

/** 路由前置守卫 */
router.beforeEach(async (to) => {
    const isAuthenticated = useUserStore().loginStatus
  
    if (whiteList.includes(to.path)) {
        // 白名单页面直接跳转，如果是跳转到login页，则判断是否已登录，已登录则跳到首页
        if (to.path === '/login' && isAuthenticated) {
            return { path: '/' }
        } else {
            return true
        }
    } else {
        // 判断是否登录
        if (!isAuthenticated) {
            return {
                path: '/login',
                query: { redirect: to.fullPath },
            }
        }
    }

    return true
})

export default router