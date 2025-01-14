// src/views/About.vue

<script setup lang="ts">

import { WindowService } from '@/services/window.service';
import { Plan } from '@/schemas/models';
import { ref, computed } from 'vue';
import { onMounted } from 'vue';

const { available_plans, default_planid } = WindowService.getMultiple({
  available_plans: null,
  default_planid: 'basic',
});
const defaultPlan = ref({} as Plan);
const anonymousPlan = ref({} as Plan);

const secondsToDays = (seconds: number) => {
  return seconds != null ? Math.floor(seconds / 86400) : 0;
};

const bytesToKB = (bytes: number) => {
  return bytes != null ? Math.round(bytes / 1024) : 0;
};

// Anonymous users can create secrets that last up to {{ anonymousTtlDays }} days
// and have a maximum size of {{ anonymousSizeKB }} KB. Free account holders get
// extended benefits: secrets can last up to {{ defaultTtlDays }} days and can be
// up to {{ defaultSizeKB }} KB in size. Account holders also get access to
// additional features like burn-before-reading options, which allow senders to
// delete secrets before they're received.
// TODO: Cleanup this mess of plans
const anonymousTtlDays = computed(() => secondsToDays(anonymousPlan?.value?.options?.ttl ?? (3600*24*7)));
const anonymousSizeKB = computed(() => bytesToKB(anonymousPlan?.value?.options?.size ?? 102400));
const defaultTtlDays = computed(() => secondsToDays(defaultPlan?.value?.options?.ttl ?? (3600*24*14)));
const defaultSizeKB = computed(() => bytesToKB(defaultPlan?.value?.options?.size ?? 1024000));

onMounted(() => {
  if (available_plans && default_planid) {
    defaultPlan.value = available_plans[default_planid] ?? null;
    anonymousPlan.value = available_plans?.anonymous;
  }
});

</script>

<template>
  <article class="prose dark:prose-invert md:prose-lg lg:prose-xl">
    <h2 class="intro">
      About Us
    </h2>

    <p class="">
      Hi, I'm <a
        href="https://delanotes.com/"
        title="Delano Mandelbaum">Delano</a>, the creator of
      Onetime Secret. What started in 2012 as a simple, secure way to share sensitive information
      has grown beyond our wildest expectations. Over a decade later, we're facilitating the secure
      sharing of millions of secrets monthly, with use cases we never imagined.
    </p>

    <p>
      The first half of 2024 has been our busiest period yet. We're grateful that people have
      continued to use and share our product for more than a decade. We're currently working on
      improvements that we think will make the service even more useful — we'll share more details
      soon.
    </p>

    <p>
      True to our roots,
      <a
        href="https://github.com/onetimesecret/onetimesecret"
        title="Fork us on GitHub">our code remains open-source</a>
      on GitHub. As we navigate the evolving landscape of digital privacy and security, we're
      committed to transparency and continual improvement.
    </p>

    <p>
      Thank you for being part of our journey. Here's to another decade of secure, ephemeral
      sharing.
    </p>

    <p class="">
      If you have any questions, there is a feedback form at the bottom of (almost) every page.
    </p>

    <p class="">
      Happy sharing,<br />Delano
    </p>

    <p style="margin-left: 40%; margin-right: 40%">
      <a
        href="https://delanotes.com/"
        title="Delano Mandelbaum"><img
          src="@/assets/img/delano-g.png"
          width="95"
          height="120"
          border="0"
        /></a>
    </p>

    <h3>F.A.Q.</h3>

    <h4>Why would I use this?</h4>
    <p>
      When you send people passwords and private links via email or chat, there are copies of that
      information stored in many places. If you use a Onetime link instead, the information persists
      for a single viewing which means it can't be read by someone else later. This allows you to
      send sensitive information in a safe way knowing it's seen by one person only. Think of it
      like a self-destructing message.
    </p>

    <h4>Why can't I send pictures or other kinds of files?</h4>
    <p>
      Our service is designed specifically for text-based secrets to ensure maximum security and
      simplicity. Files, especially images, can contain metadata that might unintentionally reveal
      information about the sender or recipient. By focusing on text, we can guarantee that no
      additional data is transmitted beyond what you explicitly type. If you need to share a file
      securely, we recommend using a dedicated secure file transfer service. We may consider adding
      support for files in the future if there are compelling use cases for it.
    </p>

    <h4>But I can copy the secret text. What's the difference?</h4>
    <p>
      True, but all you have is text. Images and other file types can contain metadata and other
      potentially revealing information about the sender or recipient. Again, this is simply to
      ensure that no private information is shared outside of the intended recipient.
    </p>

    <h4>Can I retrieve a secret that has already been shared?</h4>
    <p>Nope. We display it once and then delete it. After that, it's gone forever.</p>

    <span v-if="anonymousPlan && defaultPlan">
      <h4>What's the difference between anonymous use and having a free account?</h4>
      <p>
        Anonymous users can create secrets that last up to {{ anonymousTtlDays }} days and have a maximum size of {{ anonymousSizeKB }} KB. Free account holders get extended benefits: secrets can last up to {{ defaultTtlDays }} days and can be up to {{ defaultSizeKB }} KB in size. Account holders also get access to additional features like burn-before-reading options, which allow senders to delete secrets before they're received.
      </p>
    </span>

    <h4>How do you handle data requests from law enforcement or other third parties?</h4>
    <p>
      We designed our system with privacy in mind. We don't store secrets after they've been viewed,
      and we don't keep access logs beyond the minimum necessary. This means that in most cases, we
      simply don't have any data to provide in response to such requests. For more details, please
      review our
      <router-link to="/info/privacy">
        privacy policy
      </router-link>.
    </p>

    <h4>Why should I trust you?</h4>
    <p>
      We've designed our system with privacy and security as top priorities. Here's why you can
      trust us:
    </p>
    <ul>
      <li>
        We can't access your information even if we wanted to (which we don't). For example, if you
        share a password, we don't know the username or even the application it's for.
      </li>
      <li>
        If you use a passphrase (available under "Privacy Options"), we include that in the
        encryption key for the secret. We only store a bcrypt hash of the passphrase, making it
        impossible for us to decrypt your secret once it's saved.
      </li>
      <li>
        Our code is <a href="https://github.com/onetimesecret/onetimesecret">open source</a>. You
        can review it yourself or even run your own instance if you prefer.
      </li>
      <li>
        We use industry-standard security practices, including HTTPS for all connections and
        encryption at rest for stored data.
      </li>
    </ul>

    <h4>How does the passphrase option work?</h4>
    <p>
      When you use a passphrase, we encrypt your secret on our servers using the passphrase you
      provide. We don't store the passphrase itself, only a bcrypt hash of it. This hash is used to
      verify the passphrase when the recipient enters it. Here's why this is secure:
    </p>
    <ul>
      <li>We never store the unencrypted secret or the passphrase.</li>
      <li>The bcrypt hash cannot be used to decrypt the secret.</li>
      <li>
        Without the original passphrase, the encrypted secret cannot be decrypted, even by us.
      </li>
      <li>
        This means that even if our servers were compromised, your secret would remain secure as
        long as the passphrase remains unknown.
      </li>
    </ul>
    <p>
      Remember, the security of your secret depends on the strength of your passphrase and how
      securely you communicate it to the recipient.
    </p>
  </article>
</template>
