extends Node
## The rival pizza bikers and their (family-friendly) trash talk. `roster` holds all eight; `rivals` is the
## first Game.rival_count of them, the ones actually riding (set_count changes it).
## Placeholders: {n} = the player, {o} = another rival, {r} = the speaker.

var roster: Array = [
	{"name": "Cryptic Carl", "short": "Carl", "color": Color(0.6, 0.35, 0.9), "ftp": 238.0, "tier": 2, "speed": 3.9,
		"sig": ["Mothman delivers faster than you. Just saying.", "They don't want you to know this, but I'm winning.", "That was no pothole. That was a cover-up."]},
	{"name": "Super Sarah", "short": "Sarah", "color": Color(0.9, 0.2, 0.25), "ftp": 222.0, "tier": 1, "speed": 3.6,
		"sig": ["Have no fear, Super Sarah is here!", "My cape makes me 12% faster. Scientifically.", "I can't be late. I have to save the city. And deliver pizza."]},
	{"name": "Cadence Carla", "short": "Carla", "color": Color(0.1, 0.75, 0.75), "ftp": 262.0, "ftp_pct": 0.9, "tier": 3, "speed": 4.1,
		"sig": ["My cadence is 92. Yours is... a rumor.", "Statistically, you're losing.", "I've calculated your odds. Rounding error."]},
	{"name": "Wheelie Wanda", "short": "Wanda", "color": Color(1.0, 0.4, 0.7), "ftp": 246.0, "tier": 2, "speed": 4.0,
		"sig": ["Watch this wheelie! ...Did you watch? Rewind!", "I'm not showing off. This is just how I ride.", "Smile, I'm in your rearview mirror's highlight reel!"]},
	{"name": "Gear Grinder Gus", "short": "Gus", "color": Color(0.5, 0.4, 0.3), "ftp": 275.0, "tier": 3, "speed": 4.2,
		"sig": ["Back in my day we delivered uphill both ways.", "Kids these days and their fancy 'derailleurs'.", "I've worn out more chains than you've had hot dinners."]},
	{"name": "Margherita Maya", "short": "Maya", "color": Color(0.35, 0.8, 0.35), "ftp": 252.0, "tier": 2, "speed": 4.0,
		"sig": ["Aw, sweetie, bless your little pedals.", "I'd say good luck, but I'd be lying. Nicely.", "Don't worry, there's always second place! (It's mine, though.)"]},
	{"name": "Tubeless Tony", "short": "Tony", "color": Color(0.95, 0.85, 0.2), "ftp": 215.0, "tier": 1, "speed": 3.5,
		"sig": ["Dude. Chill. I'm winning, but, like, chill.", "Nap time after this one, bro.", "Is it already over? I was vibing."]},
	{"name": "Karate Kim", "short": "Kim", "color": Color(0.85, 0.85, 0.9), "ftp": 258.0, "tier": 3, "speed": 4.1,
		"sig": ["I'm a black belt. In pedaling, too.", "Hi-YAH! That was me passing you.", "Focus. Breathe. Win."]},
]

var _lines := {
	"race_start": [
		"Mt. Crankmore doesn't care about your feelings, {n}.",
		"I hope you stretched. Your legs will need it.",
		"Last one to the summit buys the garlic knots!",
		"Hey {n}, nice bike. Did it come with a spare tire... for your ego?",
		"Smell that? That's victory. And pepperoni.",
		"Ready to eat my dust, {n}? It's gluten-free.",
	],
	"race_pass_player": [
		"Beep beep, coming through, {n}!",
		"See you at the top, slowpoke!",
		"Bye-bye, {n}! Don't forget to breathe!",
		"Passing on the left! Crying on the right!",
		"That hill must feel steep from back there.",
	],
	"race_player_pass": [
		"Hey! No fair! I was saving my legs!",
		"Okay {n}, you can pass me. For now.",
		"Enjoy the view from the front. It won't last.",
		"Lucky move, {n}. I let you.",
		"My tire was flat. Both of them. Imaginary flats count.",
	],
	"race_leading": [
		"The front looks scary, {n}. Don't get dizzy up there.",
		"{n} is leading?! Somebody check the weather.",
		"Don't get used to it, {n}.",
	],
	"race_bear": [
		"BEAR!! Every rider for themselves!",
		"I don't have to outrun the bear, {n}. I just have to outrun YOU.",
		"Nobody make eye contact with the bear!",
		"Is that bear drafting you, {n}? Bold strategy.",
		"Throw it a pepperoni and keep pedaling!",
	],
	"race_wildlife": [
		"Oh deer. Oh deer oh deer oh deer.",
		"Watch the wildlife, {n}! They have right of way!",
		"That deer has better form than you, {n}.",
		"Even the deer are passing you, {n}.",
	],
	"race_air": [
		"Show-off! ...Okay, that was sick.",
		"Nice air, {n}! Shame about the landing. Kidding. Mostly.",
		"Did {n} just fly? Somebody check their bike for wings.",
		"Ten points for style, zero for humility.",
	],
	"race_log": [
		"Bunny hop! Look at you, {n}!",
		"Who leaves a whole tree on a race course?!",
		"Logs: one. Your rear rim: zero.",
	],
	"race_splash": [
		"Wet socks for the rest of the race, {n}! Enjoy!",
		"Hope your pizza box is waterproof!",
		"Splash zone! Splash zone!",
		"That creek is colder than your chances, {n}.",
	],
	"race_win_rival": [
		"Another victory, extra cheese. You're welcome.",
		"Winner winner pizza dinner!",
		"Too easy. Somebody get me a towel and a slice.",
		"Better luck next time, {n}. Maybe train on a smaller hill.",
	],
	"race_win_player": [
		"WHAT? {n} won?! The mountain is broken!",
		"Fine. FINE. Nice ride, {n}. I hate that I mean it.",
		"This never happened. Nobody tell my mom.",
		"Alright {n}, you've earned my respect and zero of my pizza.",
	],
	"race_lose_player": [
		"Better luck next time, {n}. Try pedaling!",
		"I'd offer you a ride down, but I'm busy winning.",
		"You looked great out there. Mostly from behind.",
		"Participation trophies are in the lobby, {n}!",
	],
	"order_stolen": [
		"Thanks for the pizza, {n}! Too slow!",
		"Mmm, that order was delicious. Well, will be.",
		"Snooze you lose, {n}!",
		"Finders keepers, pedal-pushers!",
		"The early bird gets the pepperoni.",
		"Did you take a scenic route, {n}? Because I took your order.",
	],
	"order_won": [
		"Hey! That was MY pizza, {n}!",
		"Beginner's luck, {n}. Beginner's luck.",
		"Fine, keep it. I wasn't hungry anyway.",
		"Whoa, {n} can pedal! Who knew?",
		"Enjoy it. The next one is mine.",
	],
	"delivered": [
		"Delivery complete, {n}? Cute. I did three already.",
		"A tip? You shouldn't have. (Please keep the change.)",
		"Not bad, {n}. Not great, but not bad.",
		"Look at {n}, doing real-person things.",
	],
	"late": [
		"Cold pizza, {n}? That's a breakfast, not a delivery.",
		"No pay for popsicle pepperoni, {n}!",
		"I could hear that pizza shivering from here.",
		"Pro tip, {n}: pedals go round faster than that.",
	],
	"rival_delivered": [
		"Another happy customer! Another full wallet!",
		"Delivered hot, delivered fast, delivered by me.",
		"Five stars! They wrote a poem about me. It rhymed.",
		"Cha-ching! Who needs a car when you've got calves?",
	],
	"crash_player": [
		"Ooooh, that's gonna leave a mark!",
		"Walls are not part of the route, {n}.",
		"Brakes are the lever on the left, {n}!",
		"Nice crash. I'd give it a 7.5.",
		"{n} found the building the hard way!",
	],
	"er": [
		"Say hi to the nurses, {n}!",
		"Hope you have good insurance, {n}!",
		"Cars: 1, {n}: 0.",
		"Look both ways, {n}! It's not just a suggestion!",
		"I'll deliver your pizzas while you heal. All of them.",
		"Bandages come in cheese-shaped now, I hear.",
	],
	"bike_destroyed": [
		"Rest in pieces, trusty bike.",
		"That bike had a good run. A short run, but good.",
		"Hold a moment of silence... okay, moment's over, I'm going!",
	],
	"new_bike": [
		"Ooh, shiny! Did it come with legs?",
		"A new bike won't fix your cadence, {n}.",
		"Fancy wheels! Still need to pedal them, though.",
		"Nice upgrade, {n}. I'm only a little bit scared.",
	],
	"trash_bike": [
		"Is that a bike or a cry for help, {n}?",
		"I've seen better bikes in a recycling bin.",
		"{n}, your bike called. It wants to retire.",
		"The squeaking makes a nice rhythm. Slow, though.",
		"Save up, {n}! The bike shop has actual bikes!",
	],
	"rival_crash": [
		"My bike! My beautiful bike! ...Oh, it's fine.",
		"Nobody saw that. NOBODY.",
		"That curb came out of nowhere!",
		"Ow. The ground is very hard today.",
	],
	"pu_hit_player": [
		"Special delivery, {n}! Extra cheese, extra splat.",
		"Bullseye! Pizza frisbee hall of fame, baby.",
		"Oops, did that hurt? Asking for a pepperoni.",
		"That's what we call a hot drop, {n}.",
		"Stay down there, {n}. The view's nice.",
	],
	"pu_ouch": [
		"Hey! Who throws a pizza?!",
		"I've got sauce in my ears, {n}!",
		"Not cool, {n}. Not cool at all.",
		"My jersey! This was dry clean only!",
		"I'll remember this, {n}. I have a great memory for toppings.",
	],
	"banter": [
		"{o}, your cadence is a crime scene.",
		"Hey {o}, I'll race you for the last slice!",
		"{o} still uses a bell. A BELL.",
		"{o}, your bike's so heavy it has its own gravity.",
		"Rumor has it {o} brakes for pigeons.",
		"{o}, you ride like you're delivering soup.",
		"I saw {o} stuck behind a golf cart. Embarrassing.",
		"{o}'s pizza always arrives... eventually.",
		"Is {o} even pedaling or just vibing?",
	],
	"idle": [
		"Anyone want to trade a bike for a really good pizza joke?",
		"Another day, another dozen deliveries!",
		"I could ride this town blindfolded. (I won't. Safety first.)",
		"Whistler's got nothing on Crankmore!",
		"Pro tip: pedal faster. You're welcome.",
		"Is that a bear? ...Oh, just a very hairy cyclist.",
	],
	"idle_spring": [
		"Achoo! Who planted all these tulips?",
		"Spring cleaning: I'm sweeping you off the podium, {n}.",
		"Watch out for the ducklings! ...And for me, passing you.",
		"Fresh legs, fresh blossoms, fresh pizza. Spring rules.",
	],
	"idle_summer": [
		"Summer in Crankmore: kites up, pizzas out!",
		"Somebody tell those kids I don't do frisbee. I do victory.",
		"Too hot for a jacket, perfect for a jersey.",
		"Beach volleyball later? You can be the net, {n}.",
	],
	"idle_fall": [
		"Pumpkin spice pizza. Don't knock it till you've tried it.",
		"Leaves are falling, and so are your standings, {n}.",
		"Careful, wet leaves on the corners! (I hope you slide.)",
		"Sweater weather! Still beat you in shorts.",
	],
	"idle_winter": [
		"Snow tires? Never heard of 'em.",
		"Did that snowman just pass you, {n}?",
		"Skiers on the slopes, pizza on my bike, and you behind me. Perfect winter.",
		"Hot cocoa and a hot pizza. What a day.",
		"My fingers are frozen but my legs are on fire!",
	],
}

## How a rival looks saying each kind of line (their face in the message box; see Game.racer_says). Anything not
## listed is said with a smug look.
const MOODS := {"banter": "smug", "trash_bike": "smug", "order_stolen": "smug", "race_pass_player": "smug", "race_win_rival": "smug",
	"rival_delivered": "smug", "pu_hit_player": "smug", "crash_player": "smug", "late": "smug", "er": "smug", "bike_destroyed": "smug",
	"race_leading": "smug",
	"race_player_pass": "annoyed", "race_win_player": "annoyed", "race_lose_player": "annoyed", "order_won": "annoyed", "delivered": "annoyed",
	"race_bear": "shocked", "race_wildlife": "shocked", "race_log": "shocked", "pu_ouch": "shocked", "rival_crash": "shocked", "new_bike": "shocked",
	"idle": "happy", "idle_spring": "happy", "idle_summer": "happy", "idle_fall": "happy", "idle_winter": "happy", "race_start": "happy",
	"race_air": "happy", "race_splash": "happy"}

var rivals: Array = []
var _cooldown := 0.0
var _banter_clock := 14.0


func _ready() -> void:
	set_count(Game.rival_count)


func set_count(n: int) -> void:
	# the first n of this game's lineup (a New game shuffles it); a save without one keeps the roster order
	var pool: Array = []
	for nm in Game.rival_order:
		for r in roster:
			if r["short"] == nm:
				pool.append(r)
	for r in roster:
		if not pool.has(r):
			pool.append(r)
	rivals = pool.slice(0, clampi(n, 1, pool.size()))


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func line(cat: String, rival: int, other: int = -1) -> String:
	var pool: Array = _lines.get(cat, [])
	var sig: Array = rivals[rival]["sig"]
	var text := ""
	if (cat in ["race_start", "race_win_rival", "race_pass_player", "idle", "order_stolen"]) and randf() < 0.4:
		text = sig.pick_random()
	elif pool.is_empty():
		text = sig.pick_random()
	else:
		# with a single rival there's nobody else to name, so skip lines about "{o}"
		var usable := pool if rivals.size() > 1 else pool.filter(func(l: String): return not l.contains("{o}"))
		text = usable.pick_random() if not usable.is_empty() else sig.pick_random()
	if other < 0:
		other = (rival + 1 + randi() % (rivals.size() - 1)) % rivals.size() if rivals.size() > 1 else rival
	return text.replace("{n}", Game.player_name).replace("{o}", rivals[other]["short"]).replace("{r}", rivals[rival]["short"])


## Rival speaks if the global cooldown allows (or `force`).
func say(rival: int, cat: String, force: bool = false) -> bool:
	if _cooldown > 0.0 and not force:
		return false
	_cooldown = 2.5
	var text := line(cat, rival)
	Game.rival_say.emit(rival, text)
	var who: Dictionary = rivals[rival]
	Game.racer_says.emit(String(who["short"]).to_lower(), who["name"], text, MOODS.get(cat, "smug"), who["color"])
	return true


func say_random(cat: String, force: bool = false) -> bool:
	return say(randi() % rivals.size(), cat, force)


## Call every frame during free roam; occasionally the rivals needle each other and the player.
func tick_banter(delta: float) -> void:
	_banter_clock -= delta
	if _banter_clock > 0.0:
		return
	_banter_clock = randf_range(11.0, 20.0)
	var r := randi() % rivals.size()
	var cat := "banter"
	if randf() < 0.3:
		cat = "idle" if randf() < 0.5 else "idle_" + Season.current
	elif randf() < 0.3 and Game.equipped == 0:
		cat = "trash_bike"
	say(r, cat)
