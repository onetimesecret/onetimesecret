// src/types/declarations/index.d.ts

import { ImprovedLayoutProps, LayoutProps } from '@/types/ui';
import type { AxiosResponse } from 'axios';
import type { Component } from 'vue';
import type { ScopesAvailable } from '@/types/router';

// Modify the Vue Router module augmentation
import 'vue-router';

declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean;
    layout?: Component;
    layoutProps?: LayoutProps | ImprovedLayoutProps;

    // TODO: Do a find for this key and replace with data loading approach
    initialData?: AxiosResponse<unknown>;

    domain_strategy?: string;
    display_domain?: string;
    domain_id?: string;
    site_host?: string;

    /** Scope switcher visibility configuration for this route */
    scopesAvailable?: ScopesAvailable;
  }
}
