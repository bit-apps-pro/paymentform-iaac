import { Container, getContainer } from "@cloudflare/containers";

export class PaymentformContainer extends Container {
  defaultPort = 80;
  sleepAfter = "10m";
  enableInternet = true;
  requiredPorts = [80, 443, 3000];
  onStart() {
    console.log('Container successfully started', env);
  }

  onStop() {
    console.log('Container successfully shut down');
  }

  onError(error) {
    console.log('Container error:', error);
  }
}

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);

      // Extract session ID from query params or header
      const sessionId = url.searchParams.get("sessionId") ||
        request.headers.get("X-Session-ID") ||
        "default";

      // Get the container instance for the given session ID
      const containerInstance = getContainer(env.PaymentformContainer, sessionId);

      // Pass the request to the container instance
      return containerInstance.fetch(request);
    } catch (error) {
      return new Response(`Error: ${error.message}`, {
        status: 500,
        headers: { "Content-Type": "text/plain" }
      });
    }
  }
};
