package community.morgan;

import com.google.gson.JsonObject;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import java.util.Arrays;

class BridgeProtocolTest {
 @Test void signedResponseRequiresExactRequestNonceAndKey() throws Exception {
  byte[] key=new byte[32]; Arrays.fill(key,(byte)'k');
  JsonObject response=new JsonObject();response.addProperty("nonce","request-1");response.addProperty("message","Linked");
  String encoded=BridgeProtocol.encode(response,key);
  assertEquals("Linked",BridgeProtocol.decodeResponse(encoded,key,"request-1"));
  assertThrows(Exception.class,()->BridgeProtocol.decodeResponse(encoded,key,"request-2"));
  byte[] other=new byte[32];
  assertThrows(Exception.class,()->BridgeProtocol.decodeResponse(encoded,other,"request-1"));
 }
 @Test void oversizedAndUnsignedMessagesAreRejected(){
  assertThrows(Exception.class,()->BridgeProtocol.decodeResponse("{}",new byte[32],"nonce"));
  assertThrows(Exception.class,()->BridgeProtocol.decodeResponse("x".repeat(9000),new byte[32],"nonce"));
 }
}
