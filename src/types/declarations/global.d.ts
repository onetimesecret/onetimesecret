import { OnetimeWindow } from './window';

declare global {
  interface Window extends OnetimeWindow {}
}

export {}; // Ensures the file is treated as a module
