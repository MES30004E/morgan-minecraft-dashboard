package community.morgan;

import com.google.gson.JsonObject;
import com.mojang.brigadier.arguments.StringArgumentType;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback;
import net.minecraft.server.command.ServerCommandSource;
import net.minecraft.server.network.ServerPlayerEntity;
import net.minecraft.text.Text;
import net.minecraft.server.MinecraftServer;
import net.minecraft.registry.Registries;
import net.minecraft.stat.Stats;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.fabricmc.fabric.api.networking.v1.ServerPlayConnectionEvents;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.HexFormat;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import static net.minecraft.server.command.CommandManager.argument;
import static net.minecraft.server.command.CommandManager.literal;

public final class IdentityBridge implements ModInitializer {
 private static final ThreadPoolExecutor IO=new ThreadPoolExecutor(1,2,30,TimeUnit.SECONDS,new ArrayBlockingQueue<>(64),r->{Thread t=new Thread(r,"morgan-link-io");t.setDaemon(true);return t;},new ThreadPoolExecutor.AbortPolicy());
 private int submit(ServerCommandSource source,String operation,String code,boolean confirmed){
  if(!(source.getEntity() instanceof ServerPlayerEntity player))return 0;
  if(!source.getServer().isOnlineMode()){
   player.sendMessage(Text.literal("Identity linking requires online-mode=true. No request was sent."),false);return 0;
  }
  if(code!=null&&!code.matches("[a-f0-9]{32}")){
   player.sendMessage(Text.literal("Use the 32-character pairing code shown privately on the website or in game."),false);return 0;
  }
  JsonObject value=new JsonObject();
  value.addProperty("operation",operation);
  value.addProperty("player_uuid",player.getUuidAsString());value.addProperty("player_name",player.getGameProfile().getName());value.addProperty("online_mode",true);
  value.addProperty("confirmed",confirmed);if(code!=null)value.addProperty("code",code);
  return send(player,source.getServer(),value,true);
 }
 private int send(ServerPlayerEntity player,MinecraftServer server,JsonObject value,boolean feedback){
  if(!server.isOnlineMode())return 0;
  String nonce=UUID.randomUUID().toString();
  value.addProperty("nonce",nonce);value.addProperty("issued_at",Instant.now().getEpochSecond());
  value.addProperty("player_uuid",player.getUuidAsString());value.addProperty("player_name",player.getGameProfile().getName());value.addProperty("online_mode",true);
  try{IO.execute(()->{
   String message;
   try{
    Path keyFile=Path.of(System.getenv().getOrDefault("MORGAN_LINK_SECRET_FILE","/var/lib/morgan-minecraft-link/bridge.key"));
    byte[] key=HexFormat.of().parseHex(Files.readString(keyFile).trim());
    Path socket=Path.of(System.getenv().getOrDefault("MORGAN_LINK_SOCKET","/var/lib/morgan-minecraft-link/bridge.sock"));
    String response=BridgeProtocol.exchange(socket,BridgeProtocol.encode(value,key));message=BridgeProtocol.decodeResponse(response,key,nonce);
   }catch(Exception error){message="Link service is unavailable. Your Minecraft game is unaffected. Try again later.";}
   String reply=message;
   if(feedback)server.execute(()->{if(server.getPlayerManager().getPlayer(player.getUuid())==player)player.sendMessage(Text.literal(reply),false);});
  });}catch(java.util.concurrent.RejectedExecutionException busy){if(feedback)player.sendMessage(Text.literal("Link service is busy. Try again shortly."),false);return 0;}
  return 1;
 }
 private void statistics(ServerPlayerEntity player,MinecraftServer server,boolean online){
  if(!server.isOnlineMode())return;
  var handler=player.getStatHandler();JsonObject stats=new JsonObject();
  stats.addProperty("online",online);
  stats.addProperty("play_time_ticks",handler.getStat(Stats.CUSTOM.getOrCreateStat(Stats.PLAY_TIME)));
  stats.addProperty("deaths",handler.getStat(Stats.CUSTOM.getOrCreateStat(Stats.DEATHS)));
  stats.addProperty("mob_kills",handler.getStat(Stats.CUSTOM.getOrCreateStat(Stats.MOB_KILLS)));
  long mined=0;for(var block:Registries.BLOCK)mined+=handler.getStat(Stats.MINED.getOrCreateStat(block));
  stats.addProperty("blocks_mined",mined);
  int total=0,done=0;for(var entry:server.getAdvancementLoader().getAdvancements()){
   if(entry.value().display().isPresent()){total++;if(player.getAdvancementTracker().getProgress(entry).isDone())done++;}
  }
  stats.addProperty("advancements_done",done);stats.addProperty("advancements_total",total);
  JsonObject value=new JsonObject();value.addProperty("operation","stats");value.add("statistics",stats);
  send(player,server,value,false);
 }
 @Override public void onInitialize(){
  ServerPlayConnectionEvents.JOIN.register((handler,sender,server)->statistics(handler.player,server,true));
  ServerPlayConnectionEvents.DISCONNECT.register((handler,server)->statistics(handler.player,server,false));
  final int[] ticks={0};ServerTickEvents.END_SERVER_TICK.register(server->{
   if(++ticks[0]>=6000){ticks[0]=0;for(var player:server.getPlayerManager().getPlayerList())statistics(player,server,true);}
  });
  CommandRegistrationCallback.EVENT.register((dispatcher,registryAccess,environment)->{
   dispatcher.register(literal("register").executes(c->submit(c.getSource(),"begin",null,false)));
   dispatcher.register(literal("link").executes(c->submit(c.getSource(),"begin",null,false)));
   dispatcher.register(literal("profile").executes(c->submit(c.getSource(),"profile",null,false)));
   dispatcher.register(literal("unlink").executes(c->submit(c.getSource(),"unlink",null,false)).then(literal("confirm").executes(c->submit(c.getSource(),"unlink",null,true))));
   dispatcher.register(literal("verify").then(argument("code",StringArgumentType.word()).executes(c->submit(c.getSource(),"verify",StringArgumentType.getString(c,"code"),false))
    .then(literal("confirm").executes(c->submit(c.getSource(),"verify",StringArgumentType.getString(c,"code"),true)))));
  });
 }
}
