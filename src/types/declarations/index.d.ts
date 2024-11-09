
import { AsyncDataResult } from '@/types/api/responses'
import { LayoutProps } from '@/types/ui'
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

declare module 'api' {
  export * from '../api'
}

declare module 'core' {
  export * from '../core'
}

declare module 'custom_domains' {
  export * from '../custom_domains'
}

declare module 'jurisdiction' {
  export * from '../jurisdiction'
}

declare module 'ui' {
  export * from '../ui'
}
