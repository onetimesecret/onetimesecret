# Vue Test Suite

### Commands

Running tests:`pnpm test`

### Design choices

There is a design pattern in this vue applciation where we allow stores to
bubble errors up where we handle them in the composables and/or components
(depending on complexity of the code). We do this so that we are not trying
to make decisions about whther to show the error to the user way down in
store code that has no context about what is happening in the UI. In the
composables and components is where we use wrap function. The wrap function
is also used by global vue error handler. In this way both async and sync
errors are handled by the same code for consistency.


## Recent Changes


We've successfully fixed the error handling pattern by making tests expect raw errors from stores rather than
ApplicationError format. This aligns with the proper architecture where stores bubble up errors and composables/components handle them with
useAsyncHandler.wrap().

We've reduced the failures from 16 to 10 tests. The remaining issues are mainly around:

1. domainsStore deletion - filtering logic
2. languageStore initialization - MockService and session storage coordination
3. Accept languages - browser language inclusion logic

These are more straightforward fixes compared to the architectural understanding we needed to get the error handling pattern correct.
