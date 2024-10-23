
import { createRouter, createWebHistory } from 'vue-router';

export function setupRouter() {
  return createRouter({
    history: createWebHistory(),
    routes: [
      // Define your routes here
      { path: '/signin', name: 'SignIn', component: { template: '<div>Sign In</div>' } },
      // Add other routes as needed
    ],
  });
}
