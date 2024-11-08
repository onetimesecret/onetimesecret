// src/types/api/index.ts
export * from './responses';
export * from './requests';



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
