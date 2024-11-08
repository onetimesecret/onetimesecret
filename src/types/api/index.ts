// src/types/api/index.ts
export * from './responses';
export * from './requests';

export interface ApiClient {
  get<T>(url: string): Promise<BaseApiResponse & { data: T }>;
  post<T>(url: string, data: unknown): Promise<BaseApiResponse & { data: T }>;
  put<T>(url: string, data: unknown): Promise<BaseApiResponse & { data: T }>;
  delete<T>(url: string): Promise<BaseApiResponse & { data: T }>;
}


// Base class with common properties
export class BaseEntity {
  identifier: string;
  display_name: string;
  domain: string;
  icon: string;

  constructor(identifier: string, display_name: string, domain: string, icon: string) {
    this.identifier = identifier;
    this.display_name = display_name;
    this.domain = domain;
    this.icon = icon;
  }
}
