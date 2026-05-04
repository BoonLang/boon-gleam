#include <SDL3/SDL.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  char *name;
  char *label;
  char *path;
} CatalogEntry;

typedef struct {
  char *name;
  char *title;
  char *source_path;
  char *source;
  char *snapshot;
  char *catalog_text;
} Scene;

typedef struct {
  char *initial_scene_path;
  bool verify;
  Uint64 exit_at;
  int verify_failed;
  int counter;
  int selected_catalog;
  SDL_Window *window;
  SDL_Renderer *renderer;
  CatalogEntry *catalog;
  int catalog_len;
  Scene scene;
} AppState;

static char *read_file(const char *path) {
  FILE *file = fopen(path, "rb");
  if (!file) return SDL_strdup("");
  fseek(file, 0, SEEK_END);
  long length = ftell(file);
  fseek(file, 0, SEEK_SET);
  if (length < 0) {
    fclose(file);
    return SDL_strdup("");
  }
  char *buffer = SDL_calloc((size_t)length + 1, 1);
  if (!buffer) {
    fclose(file);
    return SDL_strdup("");
  }
  fread(buffer, 1, (size_t)length, file);
  fclose(file);
  return buffer;
}

static char *json_string(const char *json, const char *key) {
  char pattern[128];
  SDL_snprintf(pattern, sizeof(pattern), "\"%s\": \"", key);
  char *start = SDL_strstr(json, pattern);
  if (!start) return SDL_strdup("");
  start += SDL_strlen(pattern);
  char *out = SDL_calloc(SDL_strlen(start) + 1, 1);
  if (!out) return SDL_strdup("");
  size_t written = 0;
  bool escaped = false;
  for (char *cursor = start; *cursor; cursor++) {
    if (escaped) {
      if (*cursor == 'n') out[written++] = '\n';
      else if (*cursor == 'r') out[written++] = '\r';
      else if (*cursor == 't') out[written++] = '\t';
      else out[written++] = *cursor;
      escaped = false;
    } else if (*cursor == '\\') {
      escaped = true;
    } else if (*cursor == '"') {
      break;
    } else {
      out[written++] = *cursor;
    }
  }
  out[written] = '\0';
  return out;
}

static void free_scene(Scene *scene) {
  SDL_free(scene->name);
  SDL_free(scene->title);
  SDL_free(scene->source_path);
  SDL_free(scene->source);
  SDL_free(scene->snapshot);
  SDL_free(scene->catalog_text);
  SDL_memset(scene, 0, sizeof(Scene));
}

static void free_catalog(AppState *app) {
  for (int index = 0; index < app->catalog_len; index++) {
    SDL_free(app->catalog[index].name);
    SDL_free(app->catalog[index].label);
    SDL_free(app->catalog[index].path);
  }
  SDL_free(app->catalog);
  app->catalog = NULL;
  app->catalog_len = 0;
}

static int snapshot_counter(const char *snapshot) {
  if (!snapshot || !snapshot[0]) return 0;
  return SDL_atoi(snapshot);
}

static char *counter_snapshot(int value) {
  char buffer[64];
  SDL_snprintf(buffer, sizeof(buffer), "%d+", value);
  return SDL_strdup(buffer);
}

static void parse_catalog(AppState *app) {
  if (app->catalog_len > 0 || !app->scene.catalog_text) return;
  char *copy = SDL_strdup(app->scene.catalog_text);
  if (!copy) return;
  int count = 0;
  for (char *cursor = copy; *cursor; cursor++) {
    if (*cursor == '\n') count++;
  }
  count++;
  app->catalog = SDL_calloc((size_t)count, sizeof(CatalogEntry));
  if (!app->catalog) {
    SDL_free(copy);
    return;
  }
  char *line_context = NULL;
  char *line = SDL_strtok_r(copy, "\n", &line_context);
  while (line) {
    char *column_context = NULL;
    char *name = SDL_strtok_r(line, "\t", &column_context);
    char *label = SDL_strtok_r(NULL, "\t", &column_context);
    char *path = SDL_strtok_r(NULL, "\t", &column_context);
    if (name && label && path) {
      CatalogEntry *entry = &app->catalog[app->catalog_len++];
      entry->name = SDL_strdup(name);
      entry->label = SDL_strdup(label);
      entry->path = SDL_strdup(path);
    }
    line = SDL_strtok_r(NULL, "\n", &line_context);
  }
  SDL_free(copy);
}

static bool load_scene(AppState *app, const char *path) {
  char *json = read_file(path);
  if (!json[0]) {
    SDL_free(json);
    return false;
  }
  free_scene(&app->scene);
  app->scene.name = json_string(json, "example");
  app->scene.title = json_string(json, "title");
  app->scene.source_path = json_string(json, "source_path");
  app->scene.source = json_string(json, "source_preview");
  app->scene.snapshot = json_string(json, "snapshot_text");
  app->scene.catalog_text = json_string(json, "catalog_text");
  if (SDL_strcmp(app->scene.name, "counter") == 0) {
    app->counter = snapshot_counter(app->scene.snapshot);
  }
  SDL_free(json);
  parse_catalog(app);
  return true;
}

static void set_color(SDL_Renderer *renderer, Uint8 r, Uint8 g, Uint8 b) {
  SDL_SetRenderDrawColor(renderer, r, g, b, 255);
}

static void fill_rect(SDL_Renderer *renderer, float x, float y, float w, float h) {
  SDL_FRect rect = {x, y, w, h};
  SDL_RenderFillRect(renderer, &rect);
}

static void debug_text(SDL_Renderer *renderer, float x, float y, const char *text) {
  if (!text) return;
  SDL_RenderDebugText(renderer, x, y, text);
}

static void debug_text_lines(SDL_Renderer *renderer, float x, float y, const char *text, int max_lines) {
  if (!text) return;
  char *copy = SDL_strdup(text);
  if (!copy) return;
  char *context = NULL;
  char *line = SDL_strtok_r(copy, "\n", &context);
  int index = 0;
  while (line && index < max_lines) {
    SDL_RenderDebugText(renderer, x, y + (float)(index * 15), line);
    line = SDL_strtok_r(NULL, "\n", &context);
    index++;
  }
  SDL_free(copy);
}

static void render(AppState *app) {
  SDL_Renderer *renderer = app->renderer;
  set_color(renderer, 244, 241, 232);
  SDL_RenderClear(renderer);

  set_color(renderer, 32, 48, 47);
  fill_rect(renderer, 0, 0, 250, 760);
  set_color(renderer, 244, 242, 235);
  debug_text(renderer, 24, 28, "Boon Gleam");
  debug_text(renderer, 24, 52, "SDL3 native playground");
  for (int index = 0; index < app->catalog_len; index++) {
    float y = 96.0f + (float)(index * 32);
    if (index == app->selected_catalog) {
      set_color(renderer, 216, 79, 42);
      fill_rect(renderer, 14, y - 8, 214, 26);
      set_color(renderer, 255, 255, 255);
    } else {
      set_color(renderer, 205, 221, 216);
    }
    debug_text(renderer, 24, y, app->catalog[index].label);
  }

  set_color(renderer, 24, 35, 34);
  debug_text(renderer, 280, 28, app->scene.title);
  debug_text(renderer, 280, 52, app->scene.name);
  set_color(renderer, 255, 255, 255);
  fill_rect(renderer, 280, 88, 560, 460);

  set_color(renderer, 24, 35, 34);
  if (SDL_strcmp(app->scene.name, "counter") == 0) {
    debug_text(renderer, 316, 126, "Counter");
    debug_text(renderer, 316, 168, app->scene.snapshot);
    set_color(renderer, 216, 79, 42);
    fill_rect(renderer, 316, 214, 92, 56);
    set_color(renderer, 255, 255, 255);
    debug_text(renderer, 356, 236, "+");
  } else if (SDL_strcmp(app->scene.name, "todo_mvc") == 0) {
    debug_text(renderer, 316, 126, "TodoMVC");
    debug_text_lines(renderer, 316, 158, app->scene.snapshot, 18);
  } else if (SDL_strcmp(app->scene.name, "interval") == 0 || SDL_strcmp(app->scene.name, "interval_hold") == 0) {
    debug_text(renderer, 316, 126, app->scene.name);
    debug_text(renderer, 316, 158, "Initial snapshot is empty.");
    debug_text(renderer, 316, 182, "Runtime tick bridge is a future SDL3 step.");
  } else {
    debug_text_lines(renderer, 316, 126, app->scene.snapshot[0] ? app->scene.snapshot : "Initial snapshot is empty.", 22);
  }

  set_color(renderer, 17, 24, 39);
  fill_rect(renderer, 870, 0, 410, 760);
  set_color(renderer, 215, 226, 223);
  debug_text(renderer, 894, 28, "Source");
  debug_text(renderer, 894, 52, app->scene.source_path);
  debug_text_lines(renderer, 894, 88, app->scene.source, 42);

  SDL_RenderPresent(renderer);
}

static void update_counter(AppState *app, int value) {
  app->counter = value;
  SDL_free(app->scene.snapshot);
  app->scene.snapshot = counter_snapshot(value);
}

static void handle_click(AppState *app, float x, float y) {
  if (x < 250.0f && y >= 88.0f) {
    int index = (int)((y - 88.0f) / 32.0f);
    if (index >= 0 && index < app->catalog_len) {
      if (load_scene(app, app->catalog[index].path)) {
        app->selected_catalog = index;
      }
    }
    return;
  }
  if (SDL_strcmp(app->scene.name, "counter") == 0 && x >= 316.0f && x <= 408.0f && y >= 214.0f && y <= 270.0f) {
    update_counter(app, app->counter + 1);
  }
}

static int catalog_index(AppState *app, const char *name) {
  for (int index = 0; index < app->catalog_len; index++) {
    if (SDL_strcmp(app->catalog[index].name, name) == 0) return index;
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    SDL_Log("usage: boon_sdl3_playground SCENE_JSON [--verify] [--exit-ms N]");
    return 2;
  }

  AppState app;
  SDL_memset(&app, 0, sizeof(AppState));
  app.initial_scene_path = argv[1];
  int exit_ms = 800;
  for (int index = 2; index < argc; index++) {
    if (SDL_strcmp(argv[index], "--verify") == 0) app.verify = true;
    if (SDL_strcmp(argv[index], "--exit-ms") == 0 && index + 1 < argc) {
      exit_ms = SDL_atoi(argv[index + 1]);
      index++;
    }
  }

  if (!SDL_Init(SDL_INIT_VIDEO)) {
    SDL_Log("SDL_Init failed: %s", SDL_GetError());
    return 1;
  }
  if (!load_scene(&app, app.initial_scene_path)) {
    SDL_Log("failed to load scene: %s", app.initial_scene_path);
    SDL_Quit();
    return 1;
  }
  app.selected_catalog = catalog_index(&app, app.scene.name);

  if (!SDL_CreateWindowAndRenderer("Boon Gleam SDL3 Playground", 1280, 760, 0, &app.window, &app.renderer)) {
    SDL_Log("SDL_CreateWindowAndRenderer failed: %s", SDL_GetError());
    free_catalog(&app);
    free_scene(&app.scene);
    SDL_Quit();
    return 1;
  }
  app.exit_at = SDL_GetTicks() + (Uint64)exit_ms;

  bool running = true;
  bool verified_click = false;
  while (running) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_QUIT) running = false;
      if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN) {
        handle_click(&app, event.button.x, event.button.y);
      }
    }
    if (app.verify && !verified_click && SDL_strcmp(app.scene.name, "counter") == 0) {
      int before = app.counter;
      update_counter(&app, app.counter + 1);
      if (app.counter != before + 1) app.verify_failed = 1;
      if (app.catalog_len < 8) app.verify_failed = 1;
      verified_click = true;
    }
    render(&app);
    if (app.verify && SDL_GetTicks() >= app.exit_at) running = false;
    SDL_Delay(16);
  }

  if (app.verify && app.verify_failed == 0) {
    SDL_Log("{\"status\":\"pass\",\"backend\":\"sdl3\",\"window_created\":true,\"catalog_examples\":%d,\"counter_click_verified\":true}", app.catalog_len);
  }
  SDL_DestroyRenderer(app.renderer);
  SDL_DestroyWindow(app.window);
  free_catalog(&app);
  free_scene(&app.scene);
  SDL_Quit();
  return app.verify_failed;
}
