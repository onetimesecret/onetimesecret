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
