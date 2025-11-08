<!-- src/components/teams/CreateTeamModal.vue -->
<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import OIcon from '@/components/icons/OIcon.vue';
import { classifyError } from '@/schemas/errors';
import { useTeamStore } from '@/stores/teamStore';
import { useOrganizationStore } from '@/stores/organizationStore';
import { createTeamPayloadSchema, type CreateTeamPayload } from '@/types/team';
import { Dialog, DialogPanel, DialogTitle, TransitionChild, TransitionRoot } from '@headlessui/vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { z } from 'zod';

const { t } = useI18n();

withDefaults(defineProps<{
  open?: boolean;
}>(), {
  open: false,
});

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'created', teamId: string): void;
}>();

const teamStore = useTeamStore();
const organizationStore = useOrganizationStore();

const formData = ref<CreateTeamPayload>({
  display_name: '',
  description: '',
  org_id: undefined,
});

const errors = ref<Record<string, string>>({});
const generalError = ref('');
const isSubmitting = ref(false);

const isFormValid = computed(() => formData.value.display_name.trim().length > 0);

const closeModal = () => {
  if (!isSubmitting.value) {
    resetForm();
    emit('close');
  }
};

const resetForm = () => {
  formData.value = {
    display_name: '',
    description: '',
    org_id: undefined,
  };
  errors.value = {};
  generalError.value = '';
};

// Load organizations on mount
onMounted(async () => {
  if (organizationStore.hasOrganizations || organizationStore.loading) return;

  try {
    await organizationStore.fetchOrganizations();
  } catch (error) {
    // Silently fail - organizations are optional
    console.debug('[CreateTeamModal] Could not load organizations:', error);
  }
});

const handleSubmit = async () => {
  if (!isFormValid.value || isSubmitting.value) return;

  errors.value = {};
  generalError.value = '';
  isSubmitting.value = true;

  try {
    // Validate form data
    createTeamPayloadSchema.parse(formData.value);

    // Create team
    const team = await teamStore.createTeam(formData.value);

    // Success - emit event and close
    emit('created', team.id);
    closeModal();
  } catch (error) {
    if (error instanceof z.ZodError && error.errors) {
      // Handle validation errors
      error.errors.forEach((err) => {
        const field = err.path[0] as string;
        errors.value[field] = err.message;
      });
    } else {
      // Handle API errors
      const classified = classifyError(error);
      generalError.value = classified.userMessage || t('web.teams.create_error');

      // Log for debugging
      console.error('[CreateTeamModal] Error creating team:', error);
    }
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <TransitionRoot
    as="template"
    :show="open"
  >
    <Dialog
      class="relative z-50"
      @close="closeModal"
    >
      <TransitionChild
        as="template"
        enter="ease-out duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0"
      >
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity dark:bg-gray-900 dark:bg-opacity-75"></div>
      </TransitionChild>

      <div class="fixed inset-0 z-10 w-screen overflow-y-auto">
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <TransitionChild
            as="template"
            enter="ease-out duration-300"
            enter-from="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
            enter-to="opacity-100 translate-y-0 sm:scale-100"
            leave="ease-in duration-200"
            leave-from="opacity-100 translate-y-0 sm:scale-100"
            leave-to="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
          >
            <DialogPanel class="relative overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg sm:p-6 dark:bg-gray-800">
              <div>
                <div class="mx-auto flex size-12 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900">
                  <OIcon
                    collection="heroicons"
                    name="users"
                    class="size-6 text-brand-600 dark:text-brand-400"
                    aria-hidden="true"
                  />
                </div>
                <div class="mt-3 text-center sm:mt-5">
                  <DialogTitle
                    as="h3"
                    class="text-base font-semibold leading-6 text-gray-900 dark:text-white"
                  >
                    {{ t('web.teams.create_team') }}
                  </DialogTitle>
                  <div class="mt-2">
                    <p class="text-sm text-gray-500 dark:text-gray-400">
                      {{ t('web.teams.create_team_description') }}
                    </p>
                  </div>
                </div>
              </div>

              <form @submit.prevent="handleSubmit" class="mt-5 sm:mt-6">
                <BasicFormAlerts
                  v-if="generalError"
                  :error="generalError"
                />

                <div class="space-y-4">
                  <!-- Team Name -->
                  <div>
                    <label
                      for="team-name"
                      class="block text-sm font-medium text-gray-700 dark:text-gray-300"
                    >
                      {{ t('web.teams.team_name') }}
                      <span class="text-red-500">*</span>
                    </label>
                    <input
                      id="team-name"
                      v-model="formData.display_name"
                      type="text"
                      required
                      maxlength="100"
                      :placeholder="t('web.teams.team_name_placeholder')"
                      :class="[
                        'mt-1 block w-full rounded-md shadow-sm sm:text-sm',
                        'focus:ring-brand-500 focus:border-brand-500',
                        'dark:bg-gray-700 dark:border-gray-600 dark:text-white dark:placeholder-gray-400',
                        errors.display_name
                          ? 'border-red-300 text-red-900 placeholder-red-300 focus:border-red-500 focus:ring-red-500'
                          : 'border-gray-300 dark:border-gray-600'
                      ]"
                    />
                    <p v-if="errors.display_name" class="mt-1 text-sm text-red-600 dark:text-red-400">
                      {{ errors.display_name }}
                    </p>
                  </div>

                  <!-- Organization (optional) -->
                  <div v-if="organizationStore.hasOrganizations">
                    <label
                      for="team-organization"
                      class="block text-sm font-medium text-gray-700 dark:text-gray-300"
                    >
                      {{ t('web.organizations.select_organization') }}
                    </label>
                    <select
                      id="team-organization"
                      v-model="formData.org_id"
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white sm:text-sm"
                    >
                      <option :value="undefined">{{ t('web.COMMON.word_none') }}</option>
                      <option
                        v-for="org in organizationStore.organizations"
                        :key="org.id"
                        :value="org.id"
                      >
                        {{ org.display_name }}
                      </option>
                    </select>
                    <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                      {{ t('web.organizations.organizations_description') }}
                    </p>
                  </div>

                  <!-- Description -->
                  <div>
                    <label
                      for="team-description"
                      class="block text-sm font-medium text-gray-700 dark:text-gray-300"
                    >
                      {{ t('web.teams.description') }}
                    </label>
                    <textarea
                      id="team-description"
                      v-model="formData.description"
                      rows="3"
                      maxlength="500"
                      :placeholder="t('web.teams.description_placeholder')"
                      :class="[
                        'mt-1 block w-full rounded-md shadow-sm sm:text-sm',
                        'focus:ring-brand-500 focus:border-brand-500',
                        'dark:bg-gray-700 dark:border-gray-600 dark:text-white dark:placeholder-gray-400',
                        errors.description
                          ? 'border-red-300 text-red-900 placeholder-red-300 focus:border-red-500 focus:ring-red-500'
                          : 'border-gray-300 dark:border-gray-600'
                      ]"
                    ></textarea>
                    <p v-if="errors.description" class="mt-1 text-sm text-red-600 dark:text-red-400">
                      {{ errors.description }}
                    </p>
                    <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                      {{ formData.description?.length || 0 }}/500
                    </p>
                  </div>
                </div>

                <div class="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense sm:grid-cols-2 sm:gap-3">
                  <button
                    type="submit"
                    :disabled="!isFormValid || isSubmitting"
                    class="inline-flex w-full justify-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 sm:col-start-2 dark:bg-brand-500 dark:hover:bg-brand-400"
                  >
                    <span v-if="!isSubmitting">{{ t('web.teams.create') }}</span>
                    <span v-else>{{ t('web.COMMON.processing') }}</span>
                  </button>
                  <button
                    type="button"
                    @click="closeModal"
                    :disabled="isSubmitting"
                    class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 sm:col-start-1 sm:mt-0 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600"
                  >
                    {{ t('web.COMMON.word_cancel') }}
                  </button>
                </div>
              </form>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
