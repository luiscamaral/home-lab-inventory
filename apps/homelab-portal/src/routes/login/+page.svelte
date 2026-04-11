<script lang="ts">
  import { enhance } from '$app/forms';
  let { form } = $props();
</script>

<div class="min-h-screen flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
  <div class="max-w-md w-full space-y-8">
    <div>
      <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900 dark:text-white">
        Sign in to Homelab
      </h2>
    </div>
    <form method="POST" use:enhance class="mt-8 space-y-6">
      {#if form?.error}
        <div class="rounded-md bg-red-50 dark:bg-red-900 p-4">
          <p class="text-sm text-red-800 dark:text-red-200">{form.error}</p>
        </div>
      {/if}
      <div class="rounded-md shadow-sm space-y-4">
        <div>
          <label for="username" class="sr-only">Username or email</label>
          <input
            id="username"
            name="username"
            type="text"
            autocomplete="username"
            required
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 dark:bg-gray-700 dark:text-white p-3"
            placeholder="Username or email"
            value={form?.username ?? ''}
          />
        </div>
        <div>
          <label for="password" class="sr-only">Password</label>
          <input
            id="password"
            name="password"
            type="password"
            autocomplete="current-password"
            required
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 dark:bg-gray-700 dark:text-white p-3"
            placeholder="Password"
          />
        </div>
      </div>

      <div>
        <button
          type="submit"
          class="w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          Sign in
        </button>
      </div>
      <div class="flex items-center justify-between text-sm">
        <a href="/forgot-password" class="text-indigo-600 hover:text-indigo-500">Forgot password?</a>
        <a href="/register" class="text-indigo-600 hover:text-indigo-500">Create account</a>
      </div>
    </form>
  </div>
</div>
