#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>
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
  char *screenshot_path;
  bool verify;
  bool screenshot_saved;
  Uint64 exit_at;
  int verify_failed;
  int counter;
  int selected_catalog;
  SDL_FRect counter_button;
  SDL_Window *window;
  SDL_Renderer *renderer;
  TTF_Font *font_regular;
  TTF_Font *font_bold;
  TTF_Font *font_title;
  TTF_Font *font_counter;
  TTF_Font *font_mono;
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

static SDL_Color color(Uint8 r, Uint8 g, Uint8 b) {
  SDL_Color c = {r, g, b, 255};
  return c;
}

static void draw_text(SDL_Renderer *renderer, TTF_Font *font, float x, float y, const char *text, SDL_Color fg) {
  if (!font || !text || !text[0]) return;
  SDL_Surface *surface = TTF_RenderText_Blended(font, text, 0, fg);
  if (!surface) return;
  SDL_Texture *texture = SDL_CreateTextureFromSurface(renderer, surface);
  if (texture) {
    SDL_FRect dst = {x, y, (float)surface->w, (float)surface->h};
    SDL_RenderTexture(renderer, texture, NULL, &dst);
    SDL_DestroyTexture(texture);
  }
  SDL_DestroySurface(surface);
}

static void draw_text_wrapped(SDL_Renderer *renderer, TTF_Font *font, float x, float y, const char *text, SDL_Color fg, int wrap_width) {
  if (!font || !text || !text[0]) return;
  SDL_Surface *surface = TTF_RenderText_Blended_Wrapped(font, text, 0, fg, wrap_width);
  if (!surface) return;
  SDL_Texture *texture = SDL_CreateTextureFromSurface(renderer, surface);
  if (texture) {
    SDL_FRect dst = {x, y, (float)surface->w, (float)surface->h};
    SDL_RenderTexture(renderer, texture, NULL, &dst);
    SDL_DestroyTexture(texture);
  }
  SDL_DestroySurface(surface);
}

static void draw_text_lines(SDL_Renderer *renderer, TTF_Font *font, float x, float y, const char *text, int max_lines, SDL_Color fg) {
  if (!text) return;
  char *copy = SDL_strdup(text);
  if (!copy) return;
  char *context = NULL;
  char *line = SDL_strtok_r(copy, "\n", &context);
  int index = 0;
  int line_skip = font ? TTF_GetFontLineSkip(font) : 18;
  while (line && index < max_lines) {
    draw_text(renderer, font, x, y + (float)(index * line_skip), line, fg);
    line = SDL_strtok_r(NULL, "\n", &context);
    index++;
  }
  SDL_free(copy);
}

static void stroke_rect(SDL_Renderer *renderer, float x, float y, float w, float h) {
  SDL_FRect rect = {x, y, w, h};
  SDL_RenderRect(renderer, &rect);
}

static void render(AppState *app) {
  SDL_Renderer *renderer = app->renderer;
  int width = 1280;
  int height = 760;
  SDL_GetCurrentRenderOutputSize(renderer, &width, &height);
  float w = (float)width;
  float h = (float)height;
  float sidebar_w = SDL_clamp(w * 0.22f, 260.0f, 360.0f);
  float gap = 24.0f;
  float source_w = w >= 1120.0f ? SDL_clamp(w * 0.30f, 360.0f, 540.0f) : 0.0f;
  float main_x = sidebar_w + gap;
  float source_x = source_w > 0.0f ? w - source_w : w;
  float main_w = source_x - main_x - gap;
  if (main_w < 420.0f) main_w = w - main_x - gap;

  SDL_Color ink = color(24, 35, 34);
  SDL_Color cream = color(244, 242, 235);
  SDL_Color muted = color(83, 97, 94);
  SDL_Color source_ink = color(215, 226, 223);

  set_color(renderer, 246, 242, 232);
  SDL_RenderClear(renderer);

  set_color(renderer, 32, 48, 47);
  fill_rect(renderer, 0, 0, sidebar_w, h);
  set_color(renderer, 244, 242, 235);
  draw_text(renderer, app->font_title, 28, 26, "Boon Gleam", cream);
  draw_text(renderer, app->font_regular, 28, 72, "SDL3 native playground", color(205, 221, 216));
  for (int index = 0; index < app->catalog_len; index++) {
    float y = 124.0f + (float)(index * 42);
    if (index == app->selected_catalog) {
      set_color(renderer, 216, 79, 42);
      fill_rect(renderer, 18, y - 12, sidebar_w - 36, 34);
      set_color(renderer, 255, 255, 255);
    } else {
      set_color(renderer, 205, 221, 216);
    }
    draw_text(renderer, app->font_bold, 28, y - 4, app->catalog[index].label, index == app->selected_catalog ? color(255, 255, 255) : color(205, 221, 216));
  }

  set_color(renderer, 24, 35, 34);
  draw_text(renderer, app->font_title, main_x, 26, app->scene.title, ink);
  draw_text(renderer, app->font_regular, main_x, 66, app->scene.name, muted);
  set_color(renderer, 255, 255, 255);
  fill_rect(renderer, main_x, 104, main_w, h - 140);
  set_color(renderer, 217, 210, 196);
  stroke_rect(renderer, main_x, 104, main_w, h - 140);

  set_color(renderer, 24, 35, 34);
  if (SDL_strcmp(app->scene.name, "counter") == 0) {
    draw_text(renderer, app->font_title, main_x + 36, 140, "Counter", ink);
    draw_text(renderer, app->font_counter, main_x + 36, 190, app->scene.snapshot, ink);
    set_color(renderer, 216, 79, 42);
    app->counter_button = (SDL_FRect){main_x + 36, 310, 128, 72};
    fill_rect(renderer, app->counter_button.x, app->counter_button.y, app->counter_button.w, app->counter_button.h);
    set_color(renderer, 255, 255, 255);
    draw_text(renderer, app->font_title, app->counter_button.x + 52, app->counter_button.y + 18, "+", color(255, 255, 255));
  } else if (SDL_strcmp(app->scene.name, "todo_mvc") == 0) {
    draw_text(renderer, app->font_title, main_x + 36, 140, "TodoMVC", ink);
    draw_text_lines(renderer, app->font_regular, main_x + 36, 188, app->scene.snapshot, 18, ink);
  } else if (SDL_strcmp(app->scene.name, "interval") == 0 || SDL_strcmp(app->scene.name, "interval_hold") == 0) {
    draw_text(renderer, app->font_title, main_x + 36, 140, app->scene.name, ink);
    draw_text(renderer, app->font_regular, main_x + 36, 188, "Initial snapshot is empty.", ink);
    draw_text(renderer, app->font_regular, main_x + 36, 220, "Runtime tick bridge is a future SDL3 step.", muted);
  } else {
    draw_text_lines(renderer, app->font_regular, main_x + 36, 140, app->scene.snapshot[0] ? app->scene.snapshot : "Initial snapshot is empty.", 22, ink);
  }

  if (source_w > 0.0f) {
    set_color(renderer, 17, 24, 39);
    fill_rect(renderer, source_x, 0, source_w, h);
    set_color(renderer, 215, 226, 223);
    draw_text(renderer, app->font_title, source_x + 24, 28, "Source", source_ink);
    draw_text_wrapped(renderer, app->font_regular, source_x + 24, 66, app->scene.source_path, color(169, 186, 182), (int)(source_w - 48.0f));
    draw_text_lines(renderer, app->font_mono, source_x + 24, 112, app->scene.source, (int)((h - 132.0f) / 17.0f), source_ink);
  }

  if (app->screenshot_path && !app->screenshot_saved) {
    SDL_Surface *surface = SDL_RenderReadPixels(app->renderer, NULL);
    if (surface) {
      if (!SDL_SaveBMP(surface, app->screenshot_path)) app->verify_failed = 1;
      SDL_DestroySurface(surface);
      app->screenshot_saved = true;
    } else {
      app->verify_failed = 1;
      app->screenshot_saved = true;
    }
  }

  SDL_RenderPresent(renderer);
}

static void update_counter(AppState *app, int value) {
  app->counter = value;
  SDL_free(app->scene.snapshot);
  app->scene.snapshot = counter_snapshot(value);
}

static void handle_click(AppState *app, float x, float y) {
  int width = 1280;
  int height = 760;
  SDL_GetCurrentRenderOutputSize(app->renderer, &width, &height);
  float sidebar_w = SDL_clamp((float)width * 0.22f, 260.0f, 360.0f);
  if (x < sidebar_w && y >= 112.0f) {
    int index = (int)((y - 112.0f) / 42.0f);
    if (index >= 0 && index < app->catalog_len) {
      if (load_scene(app, app->catalog[index].path)) {
        app->selected_catalog = index;
      }
    }
    return;
  }
  if (SDL_strcmp(app->scene.name, "counter") == 0 && x >= app->counter_button.x && x <= app->counter_button.x + app->counter_button.w && y >= app->counter_button.y && y <= app->counter_button.y + app->counter_button.h) {
    update_counter(app, app->counter + 1);
  }
}

static int catalog_index(AppState *app, const char *name) {
  for (int index = 0; index < app->catalog_len; index++) {
    if (SDL_strcmp(app->catalog[index].name, name) == 0) return index;
  }
  return 0;
}

static TTF_Font *open_font_or_log(const char *path, float size) {
  TTF_Font *font = TTF_OpenFont(path, size);
  if (!font) SDL_Log("failed to open font %s: %s", path, SDL_GetError());
  return font;
}

static bool open_fonts(AppState *app) {
  app->font_regular = open_font_or_log("/usr/share/fonts/opentype/fira/FiraSans-Medium.otf", 18.0f);
  app->font_bold = open_font_or_log("/usr/share/fonts/opentype/fira/FiraSans-SemiBold.otf", 18.0f);
  app->font_title = open_font_or_log("/usr/share/fonts/opentype/fira/FiraSans-SemiBold.otf", 28.0f);
  app->font_counter = open_font_or_log("/usr/share/fonts/opentype/fira/FiraSansCondensed-SemiBold.otf", 54.0f);
  app->font_mono = open_font_or_log("/usr/share/fonts/opentype/fira/FiraMono-Medium.otf", 14.0f);
  return app->font_regular && app->font_bold && app->font_title && app->font_counter && app->font_mono;
}

static void close_fonts(AppState *app) {
  if (app->font_regular) TTF_CloseFont(app->font_regular);
  if (app->font_bold) TTF_CloseFont(app->font_bold);
  if (app->font_title) TTF_CloseFont(app->font_title);
  if (app->font_counter) TTF_CloseFont(app->font_counter);
  if (app->font_mono) TTF_CloseFont(app->font_mono);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    SDL_Log("usage: boon_sdl3_playground SCENE_JSON [--verify] [--exit-ms N] [--screenshot PATH]");
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
    if (SDL_strcmp(argv[index], "--screenshot") == 0 && index + 1 < argc) {
      app.screenshot_path = argv[index + 1];
      index++;
    }
  }

  if (!SDL_Init(SDL_INIT_VIDEO)) {
    SDL_Log("SDL_Init failed: %s", SDL_GetError());
    return 1;
  }
  if (!TTF_Init()) {
    SDL_Log("TTF_Init failed: %s", SDL_GetError());
    SDL_Quit();
    return 1;
  }
  if (!load_scene(&app, app.initial_scene_path)) {
    SDL_Log("failed to load scene: %s", app.initial_scene_path);
    TTF_Quit();
    SDL_Quit();
    return 1;
  }
  if (!open_fonts(&app)) {
    free_catalog(&app);
    free_scene(&app.scene);
    TTF_Quit();
    SDL_Quit();
    return 1;
  }
  app.selected_catalog = catalog_index(&app, app.scene.name);

  if (!SDL_CreateWindowAndRenderer("Boon Gleam SDL3 Playground", 1440, 900, SDL_WINDOW_RESIZABLE, &app.window, &app.renderer)) {
    SDL_Log("SDL_CreateWindowAndRenderer failed: %s", SDL_GetError());
    close_fonts(&app);
    free_catalog(&app);
    free_scene(&app.scene);
    TTF_Quit();
    SDL_Quit();
    return 1;
  }
  SDL_SetWindowMinimumSize(app.window, 960, 620);
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
      render(&app);
      int before = app.counter;
      handle_click(&app, app.counter_button.x + app.counter_button.w / 2.0f, app.counter_button.y + app.counter_button.h / 2.0f);
      if (app.counter != before + 1) app.verify_failed = 1;
      if (app.catalog_len < 8) app.verify_failed = 1;
      handle_click(&app, 40.0f, 124.0f + 42.0f);
      if (SDL_strcmp(app.scene.name, "todo_mvc") != 0) app.verify_failed = 1;
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
  close_fonts(&app);
  free_catalog(&app);
  free_scene(&app.scene);
  TTF_Quit();
  SDL_Quit();
  return app.verify_failed;
}
