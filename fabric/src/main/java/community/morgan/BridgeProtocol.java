package community.morgan;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.SocketChannel;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.HexFormat;

public final class BridgeProtocol {
 private static byte[] signature(byte[] value,byte[] key) throws Exception {
  if(key.length!=32)throw new IllegalArgumentException("Invalid bridge key");
  Mac mac=Mac.getInstance("HmacSHA256");mac.init(new SecretKeySpec(key,"HmacSHA256"));return mac.doFinal(value);
 }
 public static String encode(JsonObject value,byte[] key) throws Exception {
  byte[] payload=value.toString().getBytes(StandardCharsets.UTF_8);
  JsonObject envelope=new JsonObject();
  envelope.addProperty("payload",Base64.getEncoder().encodeToString(payload));
  envelope.addProperty("mac",HexFormat.of().formatHex(signature(payload,key)));
  return envelope+"\n";
 }
 public static String decodeResponse(String raw,byte[] key,String nonce) throws Exception {
  if(raw.length()>8192)throw new IllegalArgumentException("Response too large");
  JsonObject envelope=JsonParser.parseString(raw).getAsJsonObject();
  byte[] payload=Base64.getDecoder().decode(envelope.get("payload").getAsString());
  if(!MessageDigest.isEqual(signature(payload,key),HexFormat.of().parseHex(envelope.get("mac").getAsString())))throw new SecurityException("Response authentication failed");
  JsonObject response=JsonParser.parseString(new String(payload,StandardCharsets.UTF_8)).getAsJsonObject();
  if(!nonce.equals(response.get("nonce").getAsString()))throw new SecurityException("Response nonce mismatch");
  String message=response.get("message").getAsString();
  if(message.length()>2000)throw new IllegalArgumentException("Message too large");
  return message;
 }
 private static void waitReady(SocketChannel channel,Selector selector,int operation,long deadline) throws Exception {
  long remaining=(deadline-System.nanoTime())/1_000_000;
  if(remaining<=0)throw new java.net.SocketTimeoutException("Local bridge timeout");
  channel.register(selector,operation);selector.select(Math.max(1,remaining));selector.selectedKeys().clear();
 }
 public static String exchange(Path socket,String request) throws Exception {
  long deadline=System.nanoTime()+20_000_000_000L;
  try(SocketChannel channel=SocketChannel.open(StandardProtocolFamily.UNIX);Selector selector=Selector.open()){
   channel.configureBlocking(false);
   if(!channel.connect(UnixDomainSocketAddress.of(socket))){while(!channel.finishConnect())waitReady(channel,selector,SelectionKey.OP_CONNECT,deadline);}
   ByteBuffer output=ByteBuffer.wrap(request.getBytes(StandardCharsets.UTF_8));
   while(output.hasRemaining()){if(channel.write(output)==0)waitReady(channel,selector,SelectionKey.OP_WRITE,deadline);}
   ByteArrayOutputStream response=new ByteArrayOutputStream();ByteBuffer input=ByteBuffer.allocate(1024);
   while(response.size()<=8192){
    int read=channel.read(input);if(read<0)break;
    if(read==0){waitReady(channel,selector,SelectionKey.OP_READ,deadline);continue;}
    input.flip();while(input.hasRemaining()){byte b=input.get();if(b=='\n')return response.toString(StandardCharsets.UTF_8);response.write(b);}input.clear();
   }
   throw new java.io.IOException("Incomplete bridge response");
  }
 }
}
