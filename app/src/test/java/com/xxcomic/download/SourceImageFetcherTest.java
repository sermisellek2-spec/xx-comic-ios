package com.xxcomic.download;
import org.junit.Test;
import java.io.*;
import java.net.*;
import java.nio.file.Files;
import java.util.*;
import static org.junit.Assert.*;

public class SourceImageFetcherTest {
    @Test public void encryptedTransportKeepsDecodedBytesWithoutRecompression() throws Exception {
        byte[] encrypted=Base64.getDecoder().decode("AAECAwQFBgcICQoLDA0OD54Tk4Nv+8l3Uh1THnnKXglPAH8cC/Tv25bOvDH6oRQArf7/DrKbyeVJ4noUr0XJwZLp/D3rGO6sUAtVnQsw81HqEsIN/dDPOSp+6DzeooBM");
        byte[] expected=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9AAAAABJRU5ErkJggg==");
        try(ServerSocket server=new ServerSocket(0)) {
            Thread thread=serve(server,"200 OK","application/octet-stream",encrypted.length,encrypted,new ArrayList<>());
            File output=File.createTempFile("encrypted_offline_",".part");
            try {
                new SourceImageFetcher().fetch("http://127.0.0.1:"+server.getLocalPort()+"/image","",output,Collections.emptyMap(),
                        in->com.xxcomic.source.ManwaImageDecoder.open(in,com.xxcomic.source.SourceConfig.manwa(true).route("imageKey")),()->{},file->{});
                assertArrayEquals(expected,Files.readAllBytes(output.toPath()));thread.join(2000);
            }finally{output.delete();}
        }
    }
    @Test public void successPreservesExactBytesAndHeaders() throws Exception {
        byte[] bytes={1,2,3,4};
        try(ServerSocket server=new ServerSocket(0)) {
            List<String> headers=Collections.synchronizedList(new ArrayList<>());
            Thread thread=serve(server,"200 OK","application/octet-stream",4,bytes,headers);
            File output=File.createTempFile("offline_image_",".part");
            Files.write(output.toPath(),new byte[30]); // Old entity/half-page must be truncated, never appended.
            try {
                SourceImageFetcher.Result result=new SourceImageFetcher().fetch("http://127.0.0.1:"+server.getLocalPort()+"/image","https://source/chapter",output,
                        Collections.singletonMap("User-Agent","test-agent"), in->in, ()->{}, file->{if(file.length()!=4)throw new IOException("bad image");});
                assertNotNull(result); assertEquals(4,result.bytes); assertArrayEquals(bytes,Files.readAllBytes(output.toPath()));
                thread.join(2000); assertTrue(headers.contains("Referer: https://source/chapter")); assertTrue(headers.contains("User-Agent: test-agent"));
            } finally { output.delete(); }
        }
    }
    @Test public void rejectsErrorHtmlTruncationAndUnsolicitedPartialResponse() throws Exception {
        for(String[] response:new String[][]{{"403 Forbidden","text/html","4"},{"429 Too Many Requests","text/html","4"},{"200 OK","text/html","4"},{"200 OK","image/png","40"},{"206 Partial Content","image/png","4"}}) {
            try(ServerSocket server=new ServerSocket(0)) {
                Thread thread=serve(server,response[0],response[1],Integer.parseInt(response[2]),new byte[]{1,2,3,4},new ArrayList<>());
                File output=File.createTempFile("bad_offline_",".part");
                try {
                    try {
                        new SourceImageFetcher().fetch("http://127.0.0.1:"+server.getLocalPort()+"/image","",output,Collections.emptyMap(),in->in,()->{},file->{});
                        fail("accepted "+response[0]+" "+response[1]+" length="+response[2]);
                    } catch(IOException expected) { assertFalse(output.exists()); }
                    thread.join(2000);
                } finally { output.delete(); }
            }
        }
    }
    @Test public void cancellationRemovesIncompleteFile() throws Exception {
        try(ServerSocket server=new ServerSocket(0)) {
            Thread thread=serve(server,"200 OK","image/png",4,new byte[]{1,2,3,4},new ArrayList<>());
            File output=File.createTempFile("cancel_offline_",".part");
            try {
                try {
                    new SourceImageFetcher().fetch("http://127.0.0.1:"+server.getLocalPort()+"/image","",output,Collections.emptyMap(),in->in,()->{throw new InterruptedIOException();},file->{});
                    fail("ignored cancellation");
                } catch(InterruptedIOException expected) { assertFalse(output.exists()); }
            } finally { output.delete(); }
        }
    }
    @Test public void cancellationDuringCopyRemovesAlreadyWrittenBytes() throws Exception {
        byte[] body=new byte[200000];Arrays.fill(body,(byte)7);
        try(ServerSocket server=new ServerSocket(0)) {
            Thread thread=serve(server,"200 OK","image/png",body.length,body,new ArrayList<>());
            File output=File.createTempFile("cancel_during_copy_",".part");
            try {
                assertThrows(InterruptedIOException.class,()->new SourceImageFetcher().fetch("http://127.0.0.1:"+server.getLocalPort()+"/image","",output,
                        Collections.emptyMap(),in->in,()->{if(output.length()>0)throw new InterruptedIOException();},file->{}));
                assertFalse(output.exists());thread.join(2000);
            }finally {output.delete();}
        }
    }
    private Thread serve(ServerSocket server,String status,String type,int length,byte[] body,List<String> headers) {
        Thread thread=new Thread(()->{
            try(Socket socket=server.accept()) {
                BufferedReader reader=new BufferedReader(new InputStreamReader(socket.getInputStream(),"US-ASCII"));
                for(String line;(line=reader.readLine())!=null && !line.isEmpty();) headers.add(line);
                OutputStream out=socket.getOutputStream();
                out.write(("HTTP/1.1 "+status+"\r\nContent-Type: "+type+"\r\nContent-Length: "+length+"\r\nConnection: close\r\n\r\n").getBytes("US-ASCII"));out.write(body);out.flush();
            } catch(IOException ignored) { }
        }); thread.setDaemon(true);thread.start();return thread;
    }
}
