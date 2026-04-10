<script lang="ts">
  import { enhance } from '$app/forms';
  let { form } = $props();
</script>

<div class="min-h-screen flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
  <div class="max-w-md w-full space-y-8">
    <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900 dark:text-white">
      Create an account
    </h2>

    {#if form?.success}
      <div class="rounded-md bg-green-50 dark:bg-green-900 p-4">
        <p class="text-sm text-green-800 dark:text-green-200">
          Account created! Please check your email to verify your address.
        </p>
        <a href="/login" class="mt-2 inline-block text-indigo-600 hover:text-indigo-500">Go to sign in</a>
      </div>
    {:else}
      <form method="POST" use:enhance class="mt-8 space-y-6">
        {#if form?.error}
          <div class="rounded-md bg-red-50 dark:bg-red-900 p-4">
            <p class="text-sm text-red-800 dark:text-red-200">{form.error}</p>
          </div>
        {/if}
        <div class="space-y-4">
          <input
            name="firstName"
            type="text"
            required
            placeholder="First name"
            value={form?.firstName ?? ''}
            class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
          />
          <input
            name="lastName"
            type="text"
            required
            placeholder="Last name"
            value={form?.lastName ?? ''}
            class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
          />
          <input
            name="email"
            type="email"
            autocomplete="email"
            required
            placeholder="Email"
            value={form?.email ?? ''}
            class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
          />
          <input
            name="password"
            type="password"
            autocomplete="new-password"
            required
            minlength="8"
            placeholder="Password (min 8 chars)"
            class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
          />
        </div>
        <button
          type="submit"
          class="w-full py-2 px-4 rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
        >
          Create account
        </button>
        <p class="text-center text-sm">
          Already have an account? <a href="/login" class="text-indigo-600 hover:text-indigo-500">Sign in</a>
        </p>
      </form>
    {/if}
  </div>
</div>
