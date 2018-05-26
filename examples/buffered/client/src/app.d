import std.stdio;
import std.conv;
import std.socket;
import std.concurrency;
import core.thread;
import core.stdc.errno;
import core.atomic;
import std.bitmanip;
import std.datetime;

import buffer.message;
import cryption.rsa;

mixin(LoadBufferFile!"account.buffer");

__gshared RSAKeyInfo publicKey;


void main(string[] argv)
{
    publicKey = RSA.decodeKey("AAAAIH4RaeCOInmS/CcWOrurajxk3dZ4XGEZ9MsqT3LnFqP3/uk=");
    Message.settings(615, publicKey, true);
    
    for (int i = 0; i < 10; i++)
    {
        new Thread(
            {
                go();
            }
        ).start();
    }
}

shared long total = 0;

private void go()
{
    for (int i = 0; i < 100000; i++)
    {
        i++;
        LoginRequest req = new LoginRequest();
        req.idOrMobile = "userId";
        req.password   = "******";
        req.UDID       = Clock.currTime().toUnixTime().to!string;
        req.remoteAddress = "__SERVER__CLIENT_ADDRESS__";
        ubyte[] buf = req.serialize("login");

        TcpSocket socket = new TcpSocket();
        socket.blocking = true;

        try
        {
            socket.connect(new InternetAddress("127.0.0.1", 12290));
        }
        catch(Exception e)
        {
            writeln(e.toString());
            continue;
        }

        long len;
        for (size_t off; off < buf.length; off += len)
        {
            len = socket.send(buf[off..$]);

            if (len > 0)
            {
                continue;
            }
            else if (len == 0)
            {
                writeln("Server socket close at send. Local socket: ", socket.localAddress().toString());
                socket.close();

                return;
            }
            else
            {
                writeln("Socket error at send. Local socket: ", socket.localAddress().toString());
                socket.close();

                return;
            }
        }

        ubyte[] buffer;

        buf = new ubyte[ushort.sizeof];
        len = socket.receive(buf);

        if (len != ushort.sizeof)
        {
            writeln("Socket error at receive1. Local socket: ", socket.localAddress().toString());
            socket.close();

            return;
        }

        if (buf.peek!ushort(0) != 615)
        {
            writeln("Head isn't 407. Local socket: ", socket.localAddress().toString());
            socket.close();

            return;
        }

        buffer ~= buf;
        
        buf = new ubyte[int.sizeof];
        len = socket.receive(buf);

        if (len != int.sizeof)
        {
            writeln("Socket error at receive2. Local socket: ", socket.localAddress().toString());
            socket.close();

            return;
        }
        
        size_t size = buf.peek!int(0);
        buffer ~= buf;

        buf = new ubyte[size];
        len = 0;
        for (size_t off; off < buf.length; off += len)
        {
            len = socket.receive(buf[off..$]);

            if (len > 0)
            {
                continue;
            }
            else if (len == 0)
            {
                writeln("Server socket close at receive. Local socket: ", socket.localAddress().toString());
                socket.close();

                return;
            }
            else
            {
                writeln("Socket error at receive3. Local socket: ", socket.localAddress().toString());
                socket.close();

                return;
            }
        }

        buffer ~= buf;

        core.atomic.atomicOp!"+="(total, 1);
        socket.shutdown(SocketShutdown.BOTH);
        socket.close();
        
        LoginResponse res = Message.deserialize!LoginResponse(buffer);
        writefln("result: %d, description: %s, userId: %d, token: %s, name: %s, mobile: %s", res.result, res.description, res.userId, res.token, res.name, (Clock.currTime() - SysTime.fromUnixTime(res.mobile.to!long)).total!"seconds");
    }
}