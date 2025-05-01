import "../css/app.css";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");

let Hooks = {};

console.log("Loading app.js with Hooks definition");

Hooks.VirtualizeMatchList = {
  mounted() {
    console.log("VirtualizeMatchList hook mounted");
    this.observers = new Map();
    this.visibleIdsByLeague = new Map();
    this.retryAttempts = new Map(); // Track retry attempts for each league

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
      this.retryAttempts.set(league, 0);

      const createObserverCallback = (currentLeague) => {
        return (entries) => {
          console.log(`IntersectionObserver entries for league ${currentLeague}:`, entries.length);
          entries.forEach((entry) => {
            const id = entry.target.id.replace("event-", "");
            const visibleIds = this.visibleIdsByLeague.get(currentLeague);
            if (!visibleIds) {
              console.error(`No visibleIds set for league ${currentLeague}`);
              return;
            }
            if (entry.isIntersecting) {
              visibleIds.add(id);
              console.log(`Event ${id} is visible in league ${currentLeague}`);
            } else {
              visibleIds.delete(id);
              console.log(`Event ${id} is no longer visible in league ${currentLeague}`);
            }
          });

          const visibleIdsArray = Array.from(this.visibleIdsByLeague.get(currentLeague) || new Set());
          console.log(`Visible IDs for league ${currentLeague}:`, visibleIdsArray);
          if (visibleIdsArray.length > 0) {
            const payload = {
              league: currentLeague,
              visible_ids: visibleIdsArray
            };
            console.log(`Pushing update_visible_events with payload:`, payload);
            this.pushEventWithRetry(payload, currentLeague);
          } else {
            console.log(`No visible IDs for league ${currentLeague}, skipping pushEvent`);
          }
        };
      };

      const observer = new IntersectionObserver(
        createObserverCallback(league),
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
        if (observer) {
          const events = leagueContainer.querySelectorAll("[id^='event-']");
          console.log(`Re-observing ${events.length} events in league ${league}`);
          events.forEach((event) => {
            observer.observe(event);
          });
        } else {
          console.error(`No observer found for league ${league}`);
        }
      } else {
        console.log(`League container for ${league} not found during re-observation`);
      }
    });

    this.handleEvent("update_event", (payload) => {
      const { id, data } = payload;
      const eventElement = document.getElementById(`event-${id}`);
      if (eventElement) {
        console.log(`Updating event ${id} with new data`);
        // Update time
        const timeValueElement = eventElement.querySelector('.time-value');
        if (timeValueElement) {
          if (data.et) {
            timeValueElement.textContent = this.formatTime(data.et);
          } else {
            timeValueElement.textContent = this.formatStartTime(id);
          }
        }
        // Update score
        const scoreElement = eventElement.querySelector('.score');
        if (scoreElement && data.stats && data.stats.a) {
          scoreElement.textContent = `${data.stats.a[0] || 0}:${data.stats.a[1] || 0}`;
        }
        // Update odds
        const oddsHome = eventElement.querySelector('.odds-home');
        const oddsTie = eventElement.querySelector('.odds-tie');
        const oddsAway = eventElement.querySelector('.odds-away');
        const marketOdds = this.getOdds(data, '1777');
        if (marketOdds) {
          oddsHome.textContent = marketOdds['1'] || '-';
          oddsTie.textContent = marketOdds['X'] || '-';
          oddsAway.textContent = marketOdds['2'] || '-';
        } else {
          oddsHome.textContent = '-';
          oddsTie.textContent = '-';
          oddsAway.textContent = '-';
        }
      } else {
        console.log(`Event element for ${id} not found`);
      }
    });
  },

  pushEventWithRetry(payload, league, attempt = 1) {
    const maxRetries = 3;
    this.pushEvent("update_visible_events", payload, (reply, err) => {
      if (err) {
        console.error(`Error pushing update_visible_events (attempt ${attempt}/${maxRetries}):`, err, "Reply:", reply);
        if (attempt < maxRetries) {
          console.log(`Retrying update_visible_events for league ${league}, attempt ${attempt + 1}`);
          setTimeout(() => {
            this.pushEventWithRetry(payload, league, attempt + 1);
          }, 1000); // Retry after 1 second
        } else {
          console.error(`Max retries reached for update_visible_events for league ${league}`);
        }
      } else {
        console.log("Successfully sent update_visible_events for league:", league, reply);
        this.retryAttempts.set(league, 0); // Reset retry attempts on success
      }
    });
  },

  destroyed() {
    console.log("VirtualizeMatchList hook destroyed");
    this.observers.forEach((observer) => observer.disconnect());
    this.observers.clear();
    this.visibleIdsByLeague.clear();
    this.retryAttempts.clear();
  },

  formatTime(seconds) {
    if (seconds == null) return "00:00";
    const minutes = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  },

  formatStartTime(eventId) {
    return "00:00";
  },

  getOdds(event, marketId) {
    if (!event.odds) return null;
    const market = event.odds.find(o => o.id === marketId);
    if (!market || !market.o) return null;
    return market.o.reduce((acc, odd) => {
      acc[odd.n] = odd.v;
      return acc;
    }, {});
  }
};

console.log("Hooks object defined:", Object.keys(Hooks));


let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
});

liveSocket.connect();
window.liveSocket = liveSocket;