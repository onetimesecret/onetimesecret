import 'pinia'

declare module 'pinia' {
  export interface PiniaCustomProperties {
    $logout: () => void
  }
}
