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

    /**
     * Auth feature required to access this route.
     * When set, the route guard checks bootstrapStore.authentication[feature]
     * and redirects to '/' if the feature is disabled.
     */
    requiresFeature?: 'signup' | 'signin';

    /**
     * When true, this route is excluded when SSO-only mode is active.
     * The route guard redirects authenticated users to '/account'
     * and unauthenticated users to '/signin'.
     */
    excludeSsoOnly?: boolean;

    /**
     * Minimum org membership role required to access this route.
     *
     * - 'admin': owner or admin (single-org settings/domain pages)
     * - 'owner': owner only (the organizations list at /orgs)
     *
     * Enforced by handleOrgRoleRequirement in guards.routes.ts. On single-org
     * routes the role is read from the org named by :extid/:orgid; on the list
     * page (no org in the path) the requirement is met when any membership
     * qualifies. Unmet requirements redirect to /dashboard.
     */
    requiresOrgRole?: 'owner' | 'admin';
  }
}
