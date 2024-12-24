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

    // TODO: Do a find for this key and replace with data loading approach
    initialData?: AxiosResponse<unknown>;
  }
}
