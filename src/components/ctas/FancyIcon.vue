<!-- src/components/ctas/FancyIcon.vue -->

<template>
  <svg
    xmlns="http://www.w3.org/2000/svg"
    class="size-5 transition-transform group-hover:scale-110"
    width="20"
    height="20"
    viewBox="0 0 20 20"
    fill="none">
    <defs>
      <linearGradient
        id="offKilterGradient"
        x1="0%"
        y1="0%"
        x2="100%"
        y2="100%">
        <stop
          offset="0%"
          stop-color="#EC4899">
          <animate
            attributeName="stop-color"
            values="#EC4899; #A855F7; #EAB308; #EC4899"
            dur="7s"
            repeatCount="indefinite" />
        </stop>
        <stop
          offset="100%"
          stop-color="#EAB308">
          <animate
            attributeName="stop-color"
            values="#EAB308; #EC4899; #A855F7; #EAB308"
            dur="5s"
            repeatCount="indefinite" />
        </stop>
      </linearGradient>
    </defs>
    <path
      fill-rule="evenodd"
      d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z"
      clip-rule="evenodd"
      fill="url(#offKilterGradient)">
      <animate
        attributeName="d"
        values="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z;
              M11.1 1.246A1 1 0 0112 2.2v4.8h4a1 1 0 01.82 1.573l-7.2 9.8A1 1 0 018 18v-5H3.8a1 1 0 01-.82-1.573l7.2-9.8a1 1 0 01.92-.381z;
              M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z"
        dur="10s"
        repeatCount="indefinite" />
    </path>
  </svg>
</template>
