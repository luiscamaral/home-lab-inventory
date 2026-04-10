<script lang="ts">
  import { enhance } from '$app/forms';
  let { form } = $props();
</script>

<div class="min-h-screen flex items-center justify-center py-12 px-4">
  <div class="max-w-md w-full space-y-8">
    <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900 dark:text-white">
      Reset your password
    </h2>

    {#if form?.success}
      <div class="rounded-md bg-green-50 dark:bg-green-900 p-4">
        <p class="text-sm text-green-800 dark:text-green-200">
          If an account exists with that email, we've sent a password reset link.
        </p>
        <a href="/login" class="mt-2 inline-block text-indigo-600 hover:text-indigo-500">Back to sign in</a>
      </div>
    {:else}
      <form method="POST" use:enhance class="mt-8 space-y-6">
        <input
          name="email"
          type="email"
          required
          placeholder="Email"
          class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
        />
        <button
          type="submit"
          class="w-full py-2 px-4 rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
        >
          Send reset link
        </button>
        <p class="text-center text-sm">
          <a href="/login" class="text-indigo-600 hover:text-indigo-500">Back to sign in</a>
        </p>
      </form>
    {/if}
  </div>
</div>
