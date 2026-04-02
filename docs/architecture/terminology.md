# docs/architecture/terminology.md
---
# Common Framework Terminology

| This Codebase       | Common Term                  | Framework Examples                                     |
| ------------------- | ---------------------------- | ------------------------------------------------------ |
| Logic::Base         | Service Object / Interactor / Action | Rails service objects, Laravel Actions, Phoenix Contexts |
| OrganizationContext | Request Context / Current Attributes | Rails Current.organization, Laravel auth()->user()->organization |
| authorize_domain_sso! | Policy / Authorizer          | Pundit, CanCanCan, Laravel Policies, Phoenix authorize/3 |
| raise_concerns      | Before Action / Middleware   | Rails before_action, Laravel middleware, Phoenix plugs |
| Session org → Domain org | Tenant Resolution / Scope Binding | Multi-tenancy libraries (Apartment, acts_as_tenant)    |
```
