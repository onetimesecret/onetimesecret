import { LayoutProps } from '@/types/ui';
import type { AxiosResponse } from 'axios';
import type { Component } from 'vue';

// Modify the Vue Router module augmentation
import 'vue-router';

declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean;
    layout?: Component;
    layoutProps?: LayoutProps;
    initialData?: AxiosResponse<unknown>;
  }

  interface TypedRouteParams {
    metadataKey: string; // TODO: Revisit b/c I'm pretty sure it doesn't affect anything
  }
}

declare module 'api' {
  export * from '../api';
}

declare module 'ui' {
  export * from '../ui';
}
