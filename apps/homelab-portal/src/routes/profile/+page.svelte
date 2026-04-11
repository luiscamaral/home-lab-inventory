<script lang="ts">
  import { enhance } from '$app/forms';
  let { data, form } = $props();
</script>

<div class="min-h-screen py-12 px-4">
  <div class="max-w-md mx-auto space-y-8">
    <h2 class="text-3xl font-extrabold text-gray-900 dark:text-white">Your profile</h2>

    {#if form?.success}
      <div class="rounded-md bg-green-50 dark:bg-green-900 p-4">
        <p class="text-sm text-green-800 dark:text-green-200">Profile updated successfully.</p>
      </div>
    {/if}

    {#if form?.error}
      <div class="rounded-md bg-red-50 dark:bg-red-900 p-4">
        <p class="text-sm text-red-800 dark:text-red-200">{form.error}</p>
      </div>
    {/if}

    <form method="POST" action="?/updateProfile" use:enhance class="space-y-4">
      <input
        name="firstName"
        type="text"
        required
        placeholder="First name"
        value={form?.firstName ?? data.user.firstName}
        class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
      />
      <input
        name="lastName"
        type="text"
        required
        placeholder="Last name"
        value={form?.lastName ?? data.user.lastName}
        class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
      />
      <input
        name="email"
        type="email"
        required
        placeholder="Email"
        value={form?.email ?? data.user.email}
        class="block w-full rounded-md border-gray-300 p-3 dark:bg-gray-700 dark:text-white"
      />
      <button
        type="submit"
        class="w-full py-2 px-4 rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
      >
        Update profile
      </button>
    </form>

    <form method="POST" action="?/changePassword" use:enhance class="space-y-4 pt-8 border-t">
      <h3 class="text-lg font-medium text-gray-900 dark:text-white">Change password</h3>
      <p class="text-sm text-gray-600 dark:text-gray-400">
        We'll send you an email with a link to change your password.
      </p>
      <button
        type="submit"
        class="w-full py-2 px-4 rounded-md text-white bg-gray-600 hover:bg-gray-700"
      >
        Send password change email
      </button>
    </form>

    <div class="pt-8 border-t">
      <a href="/auth/logout" class="text-red-600 hover:text-red-500">Sign out</a>
    </div>
  </div>
</div>
