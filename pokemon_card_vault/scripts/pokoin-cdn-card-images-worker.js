export default {
  async fetch(request) {
    const url = new URL(request.url);
    url.hostname = "cdn.cardcaveau.com";
    return fetch(new Request(url.toString(), request));
  },
};
