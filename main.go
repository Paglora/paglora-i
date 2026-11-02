package main

import (
	"embed"
	"log"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
)

//go:embed all:frontend/dist
var frontendAssets embed.FS

//go:embed all:payload
var payloadAssets embed.FS

func main() {
	app:=NewApp(payloadAssets)
	err:=wails.Run(&options.App{
		Title:"Paglora Installer",
		Width:770,
		Height:525,
		MinWidth:700,
		MinHeight:490,
		DisableResize:true,
		BackgroundColour:&options.RGBA{R:14,G:16,B:20,A:255},
		AssetServer:&assetserver.Options{Assets:frontendAssets},
		OnStartup:app.startup,
		Bind:[]interface{}{app},
	})
	if err!=nil {log.Fatal(err)}
}
