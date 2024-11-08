
import { LayoutProps } from '@/types/ui'
import { AsyncDataResult } from '@/types/api/responses'
import type { Component } from 'vue';

// Modify the Vue Router module augmentation
import 'vue-router';

declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean;
    layout?: Component;
    layoutProps?: LayoutProps;
    initialData?: AsyncDataResult<unknown>;
  }
}
