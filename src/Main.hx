/********************************************************************
 * PSX Launcher
 * ------------
 * Main TUI class
 * Interacts with Engine
 *
 *******************************************************************/
package;

import djNode.BaseApp;
import djNode.tools.LOG;
import djTui.WindowState;
import djTui.win.ControlsHelpBar;
import djTui.win.WindowForm;

import djTui.adaptors.djNode.InputObj;
import djTui.adaptors.djNode.TerminalObj;
import djTui.BaseElement;
import djTui.Styles;
import djTui.WM;
import djTui.Window;
import djTui.el.Button;
import djTui.el.Label;
import djTui.el.VList;
import djTui.win.MenuBar;
import djTui.win.MessageBox;
import haxe.Timer;

import djTui.WM.DB as DB;

class Main extends BaseApp
{
	// Standard program entry
	static public function main() { new Main(); }

	static var WIDTH = 80;
	static var HEIGHT = 25;
	static var WIDTH_MIN = 60;
	static var HEIGHT_MIN = 20;
	static var STATUS_POPUP_TIME:Int = 3000;

	// Instance for the app engine
	var engine:Engine;

	// Hold the windows
	var wBar:MenuBar;
	var wList:Window;
	var wGam:Window;
	var wLog:Window;
	var wInfo:Window;
	var wTag:Window;

	// Quick Pointers for the `Game Menu` RAMDRIVE buttons
	var btnStates:Array<Button> = [];
	//====================================================;

	// --
	override function init()
	{
		PROGRAM_INFO = {
			name:Engine.NAME,
			version:Engine.VER,
			author:"JohnDimi"
		};

		ARGS.Actions = [
			['cfg', "Opens the config file with the associated OS editor"],
			['install', "-Called by the NPM installer to create the config file"]
		];

		ARGS.Options = [
			['size', 'Set rendering area size. "WIDTH,HEIGHT" or "full" to use the full window area\ne.g. -size 80,20 | -size full', '1']
		];

		FLAG_USE_SLASH_FOR_OPTION = false;

		#if debug
			LOG.pipeTrace(); // all traces will redirect to LOG object
			LOG.setLogFile("a:\\psxlaunch_log.txt");
		#end

		super.init();
	}//---------------------------------------------------;

	// Hack for real terminals. Put the cursor at the end of the
	override function onExit(code:Int)
	{
		if (code == 0 && WM._isInited) T.move(0, WM.height + 1);
		super.onExit(code);
	}//---------------------------------------------------;

	// --
	// User Main entry ::
	override function onStart()
	{
		// -- Called when getting installed by NPM
		if (argsAction == "install") {
			if (Engine.NPM_install()) {
				T.print("- Created empty config file OK");
			}else{
				T.print("- Config file already exists from previous installation. Leaving as is.");
			}
			return;
		}//------

		// - First check this now, before creating the engine
		if (argsAction == "cfg") {
			T.ptag('Opening configuration file...');
			Sys.command('start ${Engine.getConfigFullpath()}');
			return;
		}//------

		// -- Create the Main Engine
		engine = new Engine();
		if (!engine.init()) {
			printBanner();
			T.ptag('\n <red>INIT ERROR : <!>${engine.ERROR}');
			T.ptag('\n <yellow>Settings file : <!>' + Engine.getConfigFullpath());
			T.ptag('\n You can also run <yellow>psxmed cfg<!> to open the config file');
			T.endl();
			waitKeyQuit();
			return;
		}//------


		if (engine.ar_games.length == 0) {
			printBanner();
			T.ptag(' - No games found in <yellow>"${engine.cfg.path_iso}"<!>\n');
			waitKeyQuit();
			return;
		}

		// -- Get size from config or parameter. Parameter can override
		parseSetSize(engine.cfg.terminal_size);
		if (argsOptions.size != null) {
			if (argsOptions.size == "full") {
				WIDTH = T.getWidth();
				HEIGHT = T.getHeight();
			}else{
				parseSetSize(argsOptions.size);
			}
		}//------

		// -- Initialize TUI ------------------------------------------
		T.setTitle(Engine.NAME);
		T.resizeTerminal(WIDTH, HEIGHT);
		T.pageDown(); T.clearScreen(); T.cursorHide();
		WM.create( new InputObj(), new TerminalObj(), WIDTH, HEIGHT, "black.1", "blue.1");

		// -- Launcher Options ------------------------------------------
		var wOpt = new WindowForm('wOpt', -2, HEIGHT -7);
			wOpt.flag_close_on_esc = true;
			wOpt.focus_lock = true;
			wOpt.setAlign("fixed", 2, 25);
			wOpt.addStack(new Label("Launcher Options Games").setColor("yellow"));
			wOpt.addSeparator();
			wOpt.addQ("Fullscreen", 'toggle,fs,false');
			wOpt.addQ("Shader", 'slOpt,shader,none|goat|sharp');
			wOpt.addStackInline( [
					new Button('ok', "Save", 1).colorFocus('black','green'),
					new Button('cancel', "Cancel", 1)
				], -1, 4, "c");	// -1 to put at the bottom of the window ,
			WM.A.screen(wOpt);
		
		// -- Main window Listing all games ---------------------
		wList = new Window("wList", WIDTH - 33, HEIGHT - 7);
			wList.pos(3, 3);
			wList.addStack(new Label("Available Games").setColor("green"));
			wList.addSeparator();
			// --
			var l = new VList(wList.inWidth, wList.inHeight - 2);
				l.flag_letter_jump = true;	// Pressing a letter will jump to it
				l.setData(engine.getGameNames());
				l.onSelect = (l2)->{
					// Dev: Hacky way to leave the highlighted element on
					l2.flag_ghost_active = true;
					wGam_open(l2.index);
					l2.flag_ghost_active = false;
				};
			wList.addStack(l);
			wList.listen((m, el)->{
				if (m == "escape") { /* Escape Key */
					WM.popupConfirm(()->Sys.exit(0), "QUIT");
				}
			});

		// -- Create the Game Options Window ---------------------
		wGam = new Window("wGam", 20, 5, Styles.win.get("red.1"));
			wGam.setPopupBehavior(); // Make it behave like a quick popup (close with esc, backspace, no tab exit)
			wGam.posNext(wList, 2).move(0, 2);
			wGam.addStack(new Button("launch", "Launch"));
			wGam.addSeparator();
			if (engine.flag_use_altsave) {
				wGam.size(wGam.width, wGam.height + 3); // Resize the window
				btnStates.push(cast wGam.addStack(new Button("pull", "Pull Save")));
				btnStates.push(cast wGam.addStack(new Button("push", "Backup Save")));
				wGam.addSeparator();
			}
			wGam.addStack(new Button("", "Close").extra("close"));
			wGam.listen(wGam_events);
			
			// Game EXT Tag ----------------------------------------------------
			// Small text below the game options, indicating game extension. etc
			
			wTag = new Window("wTag", wGam.width, 1);
				wTag.borderStyle = 0;
				wTag.addStackInline([
					new Label('Extension:'),
					new Label().setColor('darkgray')]);
				WM.A.down(wTag, wGam, 0, 1);

			
		// Small text info ----------------------------------------------
		// Flashing notification for actions (e.g. "Copied saves [OK]")
		wLog = new Window("wLog", WIDTH - 6, 1);
			wLog.focusable = false;
			wLog.modStyle({ text:"yellow", borderStyle:0});
			wLog.addStack(new Label("", wLog.inWidth, "center").setSID("log"));
			wLog.pos(3, HEIGHT - 3);
			
		winCreate_HeaderFooter();
		
		// ---------------------------------------------------------------
		
		WM.STATE.create('main', [wList]);
		WM.STATE.create('opt', [wOpt]);
		WM.STATE.goto('main');
		
		// -- Init some other things
		engine.onMednafenExit = ()->{
			var w = DB.get('nowplay');
			if (w != null) {
				DB.remove('nowplay'); w.close();
			}
			wBar.open();
			DB["foot"].open();
			wList.open(true);
		};

	}//---------------------------------------------------;


	// - Open the Game Options Popup for a target INDEX
	// - It first checks the status of the buttons, then opens the window
	function wGam_open(i:Int)
	{
		engine.prepareGame(i);
		// Only bother with checking if RAMDRIVE is enabled
		if (engine.flag_use_altsave) {
			btnStates[0].disabled = !engine.anySavesLOCAL();
			btnStates[1].disabled = !engine.anySavesRAM();
		}
		DB.get('wGam').open(true);
	}//---------------------------------------------------;


	// Window Events listener for the Game Options Window
	function wGam_events(a:String, b:BaseElement)
	{
		var opEnd = ()->{
			// Repoen the same, to refresh button status
			wGam_open(engine.index);
			// Show the previous operation LOG
			logStatus(engine.OPLOG);
		};// ------

		if (a == "close")
		{
			wList.focus();	// Sometimes it will call this after the window is closed, but it's ok
			wTag.close();

		} else if (a == "open")
		{
			wTag.open();
			var l:Label = cast wTag.getElIndex(2);
				l.text = '[' + engine.current.ext + ']';
				
		}else if (a == "fire") switch (b.SID)
		{
			case "launch":
				// Close all the windows
				DB["foot"].close();
				wGam.close(); wList.close(); wLog.close(); wTag.close();
				if (!engine.launchGame()) {
					logStatus(engine.ERROR);
					return;
				}
				var mb = MessageBox.create("Now Playing:\n" + engine.current.name , -1, null, 40, Styles.win.get("gray.1"));
				DB.set('nowplay', mb);
				mb.open(true);
			case "pull":
				engine.copySave_Pull();
				opEnd();
			case "push":
				engine.copySave_Push();
				opEnd();
			default:

		}
	}//---------------------------------------------------;





	// - Sub Function
	// Creates and adds a header/footer to the TUI
	function winCreate_HeaderFooter()
	{
		
		// : Menu Bar 
		wBar = new MenuBar("wBar", 1, 1, {bs:0, colbg:"darkcyan", colfg:"darkblue",bSmb:[1,0,0]});
			wBar.tab_mode = 1;
			wBar.setItems(["Options", "About", "Quit"]);
			WM.A.screen(wBar, "r", "t", 0);	// Align after setting the items, so that it has a width
			wBar.onSelect = (ind)-> {
				switch (ind){
					case 0:
						/// TODO: GOTO OPTIONS -->
					case 1:
						wBar.openSub( // This will resume the focused item, also will open animated
							MessageBox.create("Mednafen launcher\nCreated by JohnDimi, using Haxe", 0, null, 40),
							true);
					case 2:
						Sys.exit(0);
					default:
				}
			}
			
		// : Header
		var head = new Window( WIDTH - wBar.width, 1);
			head.focusable = false;
			// By default all windows use the default `WM.global_style_win`
			head.modStyle({
				bg:"darkcyan", text:"black", borderStyle:0, borderColor:{fg:"darkblue"}
			});
			head.padding(2, 0);
			head.addStack(new Label(PROGRAM_INFO.name + " v" + PROGRAM_INFO.version));

		// : Footer / Key help
		var foot = new ControlsHelpBar();
			foot.setData('Nav:←↑→↓|Select:Enter|Focus:Tab|Back:Esc|Quit:^c');
			foot.pos(0, HEIGHT - 1);
			DB.set("foot", foot);	// Because I want to hide/unhide this

		WM.add(head);
		WM.add(foot);
		WM.add(wBar);
	}//---------------------------------------------------;
	
	
	/**
	   Show a quick status popup. General Purpose
	   @param	s Message
	**/
	function logStatus(s:String)
	{
		if (s == null) return;
		var l:Label = cast wLog.getElIndex(1);
			l.text = s;
			wLog.open();
			l.blink(7, 180);
	}//---------------------------------------------------;


	// Set the Width/Height from a string like "80,20"
	function parseSetSize(strval:String)
	{
		var s = cast(strval, String).split(',');
		if (s != null && s.length == 2) {
			WIDTH = cast Math.max(Std.parseInt(s[0]), WIDTH_MIN);
			HEIGHT = cast Math.max(Std.parseInt(s[1]), HEIGHT_MIN);
		}else{
			throw "Cannot read Size from " + strval;
		}
	}//---------------------------------------------------;


}//-- end class --
