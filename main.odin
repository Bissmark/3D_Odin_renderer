package main

import "core:fmt"
import "core:log"
import SDL "vendor:sdl3"
import TTF "vendor:sdl3/ttf"

App :: struct {
    window: ^SDL.Window,
    renderer: ^SDL.Renderer,
    event: SDL.Event,

    font: ^TTF.Font
}

SCREEN_WIDTH :: 720
SCREEN_HEIGHT :: 560

FONT_SIZE :: 40

initialize :: proc(app: ^App) -> bool {
    TTF.Init()

    app.window = SDL.CreateWindow("3D Renderer", SCREEN_WIDTH, SCREEN_HEIGHT, {})
    if app.window == nil {
        log.error("Failed to create window:", SDL.GetError())
        return false
    }

    app.renderer = SDL.CreateRenderer(app.window, nil)
    if app.renderer == nil {
        log.error("Failed to create renderer:", SDL.GetError())
        return false
    }

    app.font = TTF.OpenFont("fonts/ShareTechMono-Regular.ttf", FONT_SIZE)
    if app.font == nil {
        log.error("Failed to load font:", SDL.GetError())
        return false
    }

    SDL.SetRenderVSync(app.renderer, 1)

    return true
}

main_loop :: proc(app: ^App) {
    for {
        for SDL.PollEvent(&app.event) {
            #partial switch app.event.type {
                case .QUIT:
                    return
            }
        }

        SDL.SetRenderDrawColor(app.renderer, 0, 0, 0, 255)
        SDL.RenderClear(app.renderer)

        SDL.RenderPresent(app.renderer)
        SDL.Delay(16)
    }
}

main :: proc() {
    fmt.printf("hello world")

    app: App

    if !initialize(&app) do return
    main_loop(&app)

    TTF.CloseFont(app.font)
    TTF.Quit()
    SDL.DestroyWindow(app.window)
    SDL.DestroyRenderer(app.renderer)
    SDL.Quit()
}