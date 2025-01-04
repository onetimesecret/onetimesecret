// plugins/pinia/initializeStores.ts

import { PiniaPluginContext } from 'pinia';

// export function initializeStores(options?: any) {
//   return ({ store }: PiniaPluginContext) => {
//     // Defer initialization to next tick to ensure all plugins have completed
//     queueMicrotask(() => {
//       if (typeof store.init === 'function') {
//         // Verify all required properties are available
//         if (!store.$api || !store.$errorHandler) {
//           console.warn(
//             `[Store ${store.$id}] Missing required properties before initialization:`,
//             {
//               hasApi: !!store.$api,
//               hasAsyncHandler: !!store.$errorHandler,
//             }
//           );
//           return;
//         }

//         store.init(options);
//       }
//     });
//   };
// }

export function initializeStores(options?: any) {
  return ({ store }: PiniaPluginContext) => {
    console.debug(`[InitializeStores] Preparing to initialize store: ${store.$id}`, {
      $api: store.$api,
      $errorHandler: store.$errorHandler,
      $logout: store.$logout,
      init: store.init
    });

    queueMicrotask(() => {
      console.debug(`[InitializeStores] Deferred check for ${store.$id}`, {
        $api: store.$api,
        $errorHandler: store.$errorHandler,
        $logout: store.$logout
      });

      if (typeof store.init === 'function') {
        if (!store.$api || !store.$errorHandler || !store.$logout) {
          console.warn(
            `[InitializeStores] Store ${store.$id} missing required properties:`,
            {
              $api: store.$api,
              $errorHandler: store.$errorHandler,
              $logout: store.$logout
            }
          );
          return;
        }

        store.init(options);
        console.debug(`[InitializeStores] Post-init state for ${store.$id}`, {
          $api: store.$api,
          $errorHandler: store.$errorHandler,
          $logout: store.$logout
        });
      }
    });
  };
}
