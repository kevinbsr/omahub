const assert = require('node:assert/strict');
const test = require('node:test');
const m = require('../MediaModel.js');
const player = {desktopEntry:'fastpotify',identity:'Spotifast',dbusName:'org.mpris.MediaPlayer2.fastpotify'};
function stream(props, serial=1) {return {ready:true,properties:{...props,'object.serial':serial},description:'',name:''};}
test('unnamed stream matches the process binary', () => {
 const node=stream({'application.name':'','application.process.binary':'fastpotify'});
 assert.deepEqual(m.streamsForPlayer(player,[node]),[node]);
 assert.equal(m.playerHasPlaybackStream(player,[node]),true);
});
test('D-Bus identity matches even when the visible and desktop names differ', () => {
 assert.equal(m.streamMatchesPlayer({...player,desktopEntry:'Spotifast'},stream({'application.process.binary':'fastpotify'})),true);
});
test('browser streams retain grouping and stable serial ordering', () => {
 const browser={desktopEntry:'brave-browser',identity:'Brave',dbusName:'org.mpris.MediaPlayer2.brave.instance147533'};
 const a=stream({'application.name':'Brave'},20), b=stream({'application.process.binary':'brave'},10);
 assert.deepEqual(m.streamsForPlayer(browser,[a,b]),[b,a]);
});
test('unrelated and unresolved streams are not claimed', () => {
 const other=stream({'application.process.binary':'brave'});
 assert.deepEqual(m.streamsForPlayer(player,[other,stream({}),{ready:false,properties:{'application.process.binary':'fastpotify'}}]),[]);
 assert.deepEqual(m.streamsForPlayer(null,[other]),[]);
 assert.deepEqual(m.streamsForPlayer(player,null),[]);
});
test('short identifiers do not match substrings', () => {
 assert.equal(m.streamMatchesPlayer({identity:'mpv'},stream({'application.name':'mpvhelper'})),false);
});

test('cover focus prefers the matching track window within the correct app', () => {
 const browser={desktopEntry:'brave',trackTitle:'Example song'};
 const unrelated={appId:'foot',title:'Example song',activated:true};
 const active={appId:'brave-origin',title:'Other page',activated:true};
 const playing={appId:'brave-origin',title:'Example song - YouTube'};
 assert.equal(m.windowForPlayer(browser,[unrelated,active,playing]),playing);
 assert.equal(m.windowForPlayer(player,[{appId:'fastpotify',title:'Track'}]).appId,'fastpotify');
 assert.equal(m.windowForPlayer(null,[playing]),null);
 assert.equal(m.windowForPlayer(player,[unrelated]),null);
});

test('cover focus accepts QML list-like window collections', () => {
 const window={appId:'fastpotify',title:'Track'};
 assert.equal(m.windowForPlayer(player,{0:window,length:1}),window);
});
