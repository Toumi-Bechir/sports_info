defmodule SportsInfoWeb.Layouts do
  use SportsInfoWeb, :html

  embed_templates "layouts/*"

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
        <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
        <title>SportsInfo</title>
        <link rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer type="text/javascript" src={~p"/assets/app.js"}></script>
      </head>
      <body class="bg-gray-900 text-white">
        <!-- Top Navigation Bar -->
        <nav class="bg-green-900 p-2 flex justify-between items-center">
          <div class="text-yellow-400 font-bold text-xl">SportsInfo</div>
          <div class="flex space-x-4">
            <a href="#" class="text-white hover:text-yellow-400">ALL SPORTS</a>
            <a href="#" class="text-white hover:text-yellow-400">LIVE IN GAME</a>
            <a href="#" class="text-white hover:text-yellow-400">CASINO</a>
            <button class="bg-yellow-400 text-black px-4 py-1 rounded">Join</button>
            <button class="bg-green-600 text-white px-4 py-1 rounded">Log In</button>
          </div>
        </nav>

        <!-- Main Content with Sidebar -->
        <div class="flex">
          <!-- Sidebar (Sports Selection) -->
          <aside class="w-16 bg-gray-800 p-2 md:w-48 md:p-4">
            <div class="flex flex-col space-y-2">
              <!-- Sports Icons -->
              <button class="p-2 bg-gray-700 rounded hover:bg-gray-600">
                <svg class="w-6 h-6 mx-auto" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
                </svg>
                <span class="hidden md:block text-center text-sm">Favorites</span>
              </button>
              <button class="p-2 bg-gray-700 rounded hover:bg-gray-600">
                <svg class="w-6 h-6 mx-auto" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
                </svg>
                <span class="hidden md:block text-center text-sm">Basketball</span>
              </button>
              <button class="p-2 bg-gray-700 rounded hover:bg-gray-600">
                <svg class="w-6 h-6 mx-auto" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
                </svg>
                <span class="hidden md:block text-center text-sm">Baseball</span>
              </button>
              <button class="p-2 bg-gray-700 rounded hover:bg-gray-600">
                <svg class="w-6 h-6 mx-auto" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
                </svg>
                <span class="hidden md:block text-center text-sm">Hockey</span>
              </button>
              <button class="p-2 bg-gray-600 rounded">
                <svg class="w-6 h-6 mx-auto" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
                </svg>
                <span class="hidden md:block text-center text-sm">Soccer</span>
              </button>
              <!-- Add more sports as needed -->
            </div>
          </aside>

          <!-- Main Content -->
          <main class="flex-1 p-4">
            <%= @inner_content %>
          </main>
        </div>
      </body>
    </html>
    """
  end
end