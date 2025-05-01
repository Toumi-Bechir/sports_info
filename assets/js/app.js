import "../css/app.css";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");

let Hooks = {};

// Debug log to confirm app.js version
console.log("Loading app.js with Hooks definition");

Hooks.VirtualizeMatchList = {
  mounted() {
    console.log("VirtualizeMatchList hook mounted");
    this.observers = new Map();
    this.visibleIdsByLeague = new Map();

    const leagueContainers = this.el.querySelectorAll("[data-league]");
    console.log("Found league containers:", leagueContainers.length);
    leagueContainers.forEach((leagueContainer) => {
      const league = leagueContainer.dataset.league;
      if (!league) {
        console.error("League container missing data-league attribute:", leagueContainer);
        return;
      }
      console.log("Setting up observer for league:", league);
      this.visibleIdsByLeague.set(league, new Set());

      const observer = new IntersectionObserver(
        (entries) => {
          console.log(`IntersectionObserver entries for league ${league}:`, entries.length);
          entries.forEach((entry) => {
            const id = entry.target.id.replace("event-", "");
            const visibleIds = this.visibleIdsByLeague.get(league);
            if (entry.isIntersecting) {
              visibleIds.add(id);
              console.log(`Event ${id} is visible in league ${league}`);
            } else {
              visibleIds.delete(id);
              console.log(`Event ${id} is no longer visible in league ${league}`);
            }
          });
          const visibleIdsArray = Array.from(this.visibleIdsByLeague.get(league));
          console.log(`Visible IDs for league ${league}:`, visibleIdsArray);
          if (visibleIdsArray.length > 0) {
            this.pushEvent("update_visible_events", {
              league: league,
              visible_ids: visibleIdsArray
            }, (reply, err) => {
              if (err) {
                console.error("Error pushing update_visible_events:", err);
              } else {
                console.log("Successfully sent update_visible_events for league:", league, reply);
              }
            });
          } else {
            console.log(`No visible IDs for league ${league}, skipping pushEvent`);
          }
        },
        {
          root: null,
          rootMargin: "200px",
          threshold: 0
        }
      );

      this.observers.set(league, observer);

      const events = leagueContainer.querySelectorAll("[id^='event-']");
      console.log(`Observing ${events.length} events in league ${league}`);
      events.forEach((event) => {
        observer.observe(event);
      });
    });

    this.handleEvent("update_visible_events", ({ league }) => {
      console.log(`Received update_visible_events event for league ${league}, re-observing...`);
      const leagueContainer = this.el.querySelector(`[data-league="${league}"]`);
      if (leagueContainer) {
        const observer = this.observers.get(league);
        const events = leagueContainer.querySelectorAll("[id^='event-']");
        console.log(`Re-observing ${events.length} events in league ${league}`);
        events.forEach((event) => {
          observer.observe(event);
        });
      } else {
        console.log(`League container for ${league} not found during re-observation`);
      }
    });
  },

  destroyed() {
    console.log("VirtualizeMatchList hook destroyed");
    this.observers.forEach((observer) => observer.disconnect());
    this.observers.clear();
    this.visibleIdsByLeague.clear();
  },
};

Hooks.InfiniteScroll = {
  mounted() {
    console.log("InfiniteScroll hook mounted");
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          const allLoaded = this.el.dataset.allLoaded === "true";
          if (!allLoaded) {
            console.log("Infinite scroll trigger visible, loading more events");
            this.pushEvent("load_more", {});
          } else {
            console.log("All events loaded, stopping infinite scroll");
          }
        }
      },
      {
        root: null,
        rootMargin: "200px",
        threshold: 0
      }
    );

    this.observer.observe(this.el);
  },

  destroyed() {
    console.log("InfiniteScroll hook destroyed");
    this.observer.disconnect();
  }
};

// Debug logs to confirm Hooks object contents
console.log("Hooks object defined:", Object.keys(Hooks));
console.log("InfiniteScroll hook defined:", Hooks.InfiniteScroll ? "Yes" : "No");


let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
});

liveSocket.connect();
window.liveSocket = liveSocket;