<script lang="ts">
  let { data } = $props();
</script>

<div class="min-h-screen flex items-center justify-center px-4">
  <div class="max-w-md w-full text-center space-y-8">
    <h1 class="text-4xl font-extrabold text-gray-900 dark:text-white">Homelab Portal</h1>

    {#if data.user}
      <div class="space-y-4">
        <p class="text-gray-600 dark:text-gray-400">Signed in as <strong>{data.user.email}</strong></p>
        <div class="flex gap-4 justify-center">
          <a href="/profile" class="px-6 py-3 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
            Profile
          </a>
          <a href="/auth/logout" class="px-6 py-3 bg-gray-600 text-white rounded-md hover:bg-gray-700">
            Sign out
          </a>
        </div>
      </div>
    {:else}
      <div class="space-y-4">
        <p class="text-gray-600 dark:text-gray-400">Please sign in to continue.</p>
        <div class="flex gap-4 justify-center">
          <a href="/login" class="px-6 py-3 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
            Sign in
          </a>
          <a href="/register" class="px-6 py-3 bg-gray-600 text-white rounded-md hover:bg-gray-700">
            Register
          </a>
        </div>
      </div>
    {/if}
  </div>
</div>
