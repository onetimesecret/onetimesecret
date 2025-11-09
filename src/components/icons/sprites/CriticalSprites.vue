<!-- src/components/icons/sprites/CriticalSprites.vue -->
<!--
Critical SVG sprites for immediate availability during initial page render.

This is a performance optimization collection containing duplicates of essential icons
from their original sprite libraries. Icons remain in their canonical locations
(HeroiconsSprites.vue, MaterialSymbolsSprites.vue, etc.) for consistency.

Purpose: Prevent Flash of Missing Icons (FOMI) for above-the-fold content by ensuring
critical UI elements have immediate icon availability.

License: Mixed - icons sourced from original libraries, see individual comments
Usage:
    <svg>
      <use href="#material-symbols-settings-outline"></use>
    </svg>

Note: These icons also exist in their original sprite files. Both references point
to identical icons, so use whichever ID is more convenient for your use case.
-->
<template>
  <svg
    xmlns="http://www.w3.org/2000/svg"
    xmlns:xlink="http://www.w3.org/1999/xlink">
    <defs>
      <!-- Settings icon - Material Symbols -->
      <symbol
        viewBox="0 0 24 24"
        id="material-symbols-settings-outline">
        <path
          fill="currentColor"
          d="m9.25 22l-.4-3.2q-.325-.125-.612-.3t-.563-.375L4.7 19.375l-2.75-4.75l2.575-1.95Q4.5 12.5 4.5 12.338v-.675q0-.163.025-.338L1.95 9.375l2.75-4.75l2.975 1.25q.275-.2.575-.375t.6-.3l.4-3.2h5.5l.4 3.2q.325.125.613.3t.562.375l2.975-1.25l2.75 4.75l-2.575 1.95q.025.175.025.338v.674q0 .163-.05.338l2.575 1.95l-2.75 4.75l-2.95-1.25q-.275.2-.575.375t-.6.3l-.4 3.2zM11 20h1.975l.35-2.65q.775-.2 1.438-.587t1.212-.938l2.475 1.025l.975-1.7l-2.15-1.625q.125-.35.175-.737T17.5 12t-.05-.787t-.175-.738l2.15-1.625l-.975-1.7l-2.475 1.05q-.55-.575-1.212-.962t-1.438-.588L13 4h-1.975l-.35 2.65q-.775.2-1.437.588t-1.213.937L5.55 7.15l-.975 1.7l2.15 1.6q-.125.375-.175.75t-.05.8q0 .4.05.775t.175.75l-2.15 1.625l.975 1.7l2.475-1.05q.55.575 1.213.963t1.437.587zm1.05-4.5q1.45 0 2.475-1.025T15.55 12t-1.025-2.475T12.05 8.5q-1.475 0-2.488 1.025T8.55 12t1.013 2.475T12.05 15.5M12 12" />
      </symbol>

      <!-- Logout icon - Heroicons (arrow-right-on-rectangle-solid from App.vue) -->
      <symbol
        viewBox="0 0 24 24"
        id="heroicons-arrow-right-on-rectangle-solid">
        <path
          fill="currentColor"
          fill-rule="evenodd"
          d="M16.5 3.75a1.5 1.5 0 0 1 1.5 1.5v13.5a1.5 1.5 0 0 1-1.5 1.5h-6a1.5 1.5 0 0 1-1.5-1.5V15a.75.75 0 0 0-1.5 0v3.75a3 3 0 0 0 3 3h6a3 3 0 0 0 3-3V5.25a3 3 0 0 0-3-3h-6a3 3 0 0 0-3 3V9A.75.75 0 1 0 9 9V5.25a1.5 1.5 0 0 1 1.5-1.5h6Zm-5.03 4.72a.75.75 0 0 0 0 1.06l1.72 1.72H2.25a.75.75 0 0 0 0 1.5h10.94l-1.72 1.72a.75.75 0 1 0 1.06 1.06l3-3a.75.75 0 0 0 0-1.06l-3-3a.75.75 0 0 0-1.06 0Z"
          clip-rule="evenodd" />
      </symbol>

      <!-- Globe icon - Font Awesome 6 Solid (fa6-solid-globe) -->
      <symbol
        viewBox="0 0 512 512"
        id="fa6-solid-globe">
        <path
          fill="currentColor"
          d="M352 256c0 22.2-1.2 43.6-3.3 64H163.3c-2.2-20.4-3.3-41.8-3.3-64s1.2-43.6 3.3-64H348.7c2.2 20.4 3.3 41.8 3.3 64zm28.8-64H503.9c5.3 20.5 8.1 41.9 8.1 64s-2.8 43.5-8.1 64H380.8c2.1-20.6 3.2-42 3.2-64s-1.1-43.4-3.2-64zm112.6-32H376.7c-10-63.9-29.8-117.4-55.3-151.6c78.3 20.7 142 77.5 171.9 151.6zm-149.1 0H167.7c6.1-36.4 15.5-68.6 27-94.7c10.5-23.6 22.2-40.7 33.5-51.5C239.4 3.2 248.7 0 256 0s16.6 3.2 27.8 13.8c11.3 10.8 23 27.9 33.5 51.5c11.6 26 20.9 58.2 27 94.7zm-209 0H8.1C38 85.6 101.7 28.8 180 8.1C154.5 42.3 134.7 95.8 124.7 160h0zM8.1 192H131.2c-2.1 20.6-3.2 42-3.2 64s1.1 43.4 3.2 64H8.1C2.8 299.5 0 278.1 0 256s2.8-43.5 8.1-64zM167.7 352c-6.1 36.4-15.5 68.6-27 94.7c-10.5 23.6-22.2 40.7-33.5 51.5C96 509.8 86.7 512 79.1 512H79c-7.1 0-13.9-2.2-18.4-7.2c-4.5-5-6.6-11.5-6.6-18.8s2.1-13.8 6.6-18.8c4.5-5 11.3-7.2 18.4-7.2h.1c6.6 0 16.9 2.2 28.2-8.8c11.3-10.8 23-27.9 33.5-51.5c11.6-26 20.9-58.2 27-94.7zm21 160c25.5-34.2 45.3-87.7 55.3-151.6H376.7c-10 63.9-29.8 117.4-55.3 151.6C300.2 532.8 278.1 544 256 544s-44.2-11.2-65.3-32z" />
      </symbol>

      <!-- Menu icon - Heroicons (bars-3) -->
      <symbol
        viewBox="0 0 24 24"
        id="heroicons-bars-3">
        <path
          fill="currentColor"
          fill-rule="evenodd"
          d="M3 6.75A.75.75 0 0 1 3.75 6h16.5a.75.75 0 0 1 0 1.5H3.75A.75.75 0 0 1 3 6.75ZM3 12a.75.75 0 0 1 .75-.75h16.5a.75.75 0 0 1 0 1.5H3.75A.75.75 0 0 1 3 12Zm0 5.25a.75.75 0 0 1 .75-.75h16.5a.75.75 0 0 1 0 1.5H3.75a.75.75 0 0 1-.75-.75Z"
          clip-rule="evenodd" />
      </symbol>

      <!-- Close/X icon - Heroicons (x-mark-16-solid) -->
      <symbol
        viewBox="0 0 16 16"
        id="heroicons-x-mark-16-solid">
        <path
          fill="currentColor"
          d="M5.28 4.22a.75.75 0 0 0-1.06 1.06L6.94 8l-2.72 2.72a.75.75 0 1 0 1.06 1.06L8 9.06l2.72 2.72a.75.75 0 1 0 1.06-1.06L9.06 8l2.72-2.72a.75.75 0 0 0-1.06-1.06L8 6.94z" />
      </symbol>

      <!-- User icon - Heroicons (user-solid) -->
      <symbol
        viewBox="0 0 24 24"
        id="heroicons-user-solid">
        <path
          fill="currentColor"
          fill-rule="evenodd"
          d="M7.5 6a4.5 4.5 0 1 1 9 0 4.5 4.5 0 0 1-9 0ZM3.751 20.105a8.25 8.25 0 0 1 16.498 0 .75.75 0 0 1-.437.695A18.683 18.683 0 0 1 12 22.5c-2.786 0-5.433-.608-7.812-1.7a.75.75 0 0 1-.437-.695Z"
          clip-rule="evenodd" />
      </symbol>

      <!-- Lock icon - Heroicons (lock-closed-solid) -->
      <symbol
        viewBox="0 0 24 24"
        id="heroicons-lock-closed-solid">
        <path
          fill="currentColor"
          fill-rule="evenodd"
          d="M12 1.5a5.25 5.25 0 0 0-5.25 5.25v3a3 3 0 0 0-3 3v6.75a3 3 0 0 0 3 3h10.5a3 3 0 0 0 3-3v-6.75a3 3 0 0 0-3-3v-3c0-2.9-2.35-5.25-5.25-5.25Zm3.75 8.25v-3a3.75 3.75 0 1 0-7.5 0v3h7.5Z"
          clip-rule="evenodd" />
      </symbol>

      <!-- Eye icon (show) - Heroicons (eye-solid) -->
      <symbol
        viewBox="0 0 24 24"
        id="heroicons-eye-solid">
        <path
          fill="currentColor"
          d="M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z" />
        <path
          fill="currentColor"
          fill-rule="evenodd"
          d="M1.323 11.447C2.811 6.976 7.028 3.75 12.001 3.75c4.97 0 9.185 3.223 10.675 7.69.12.362.12.752 0 1.113-1.487 4.471-5.705 7.697-10.677 7.697-4.97 0-9.186-3.223-10.675-7.69a1.762 1.762 0 0 1 0-1.113ZM17.25 12a5.25 5.25 0 1 1-10.5 0 5.25 5.25 0 0 1 10.5 0Z"
          clip-rule="evenodd" />
      </symbol>

      <!-- Eye slash icon (hide) - Heroicons (eye-slash-solid) -->
      <symbol
        viewBox="0 0 24 24"
        id="heroicons-eye-slash-solid">
        <path
          fill="currentColor"
          d="M3.53 2.47a.75.75 0 0 0-1.06 1.06l18 18a.75.75 0 1 0 1.06-1.06l-18-18ZM22.676 12.553a11.249 11.249 0 0 1-2.631 4.31l-3.099-3.099a5.25 5.25 0 0 0-6.71-6.71L7.759 4.577a11.217 11.217 0 0 1 4.242-.827c4.97 0 9.185 3.223 10.675 7.69.12.362.12.752 0 1.113Z" />
        <path
          fill="currentColor"
          d="M15.75 12c0 .18-.013.357-.037.53l-4.244-4.243A3.75 3.75 0 0 1 15.75 12ZM12.53 15.713l-4.243-4.244a3.75 3.75 0 0 0 4.244 4.243Z" />
        <path
          fill="currentColor"
          d="M6.75 12c0-.619.107-1.213.304-1.764l-3.1-3.1a11.25 11.25 0 0 0-2.63 4.31c-.12.362-.12.752 0 1.114 1.489 4.467 5.704 7.69 10.675 7.69 1.5 0 2.933-.294 4.242-.827l-2.477-2.477A5.25 5.25 0 0 1 6.75 12Z" />
      </symbol>
    </defs>
  </svg>
</template>
