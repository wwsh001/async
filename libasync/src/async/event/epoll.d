module async.event.epoll;

debug import std.stdio;

version (linux):

import core.sys.linux.epoll;
import core.stdc.errno;
import core.sys.posix.signal;
import core.sys.posix.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.time;

import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;

alias LoopSelector = Epoll;

class Epoll : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError, int workerThreadNum)
    {
        super(listener, onConnected, onDisConnected, onReceive, onSendCompleted, onSocketError, workerThreadNum);

        _eventHandle = epoll_create1(0);
        register(_listener.fd, EventType.ACCEPT);
    }

    override bool register(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        epoll_event ev;
        ev.events  = EPOLLHUP | EPOLLERR;
        ev.data.fd = fd;

        if (et != EventType.ACCEPT)
        {
            ev.events |= EPOLLET;
        }
        if (et == EventType.ACCEPT || et == EventType.READ || et == EventType.READWRITE)
        {
            ev.events |= EPOLLIN;
        }
        if ((et == EventType.WRITE) || (et == EventType.READWRITE))
        {
            ev.events |= EPOLLOUT;
        }

        if (epoll_ctl(_eventHandle, EPOLL_CTL_ADD, fd, &ev) != 0)
        {
            if (errno != EEXIST)
            {
                return false;
            }
        }

        return true;
    }

    override bool reregister(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        epoll_event ev;
        ev.events  = EPOLLHUP | EPOLLERR;
        ev.data.fd = fd;

        if (et != EventType.ACCEPT)
        {
            ev.events |= EPOLLET;
        }
        if (et == EventType.ACCEPT || et == EventType.READ || et == EventType.READWRITE)
        {
            ev.events |= EPOLLIN;
        }
        if ((et == EventType.WRITE) || (et == EventType.READWRITE))
        {
            ev.events |= EPOLLOUT;
        }

        return (epoll_ctl(_eventHandle, EPOLL_CTL_MOD, fd, &ev) == 0);
    }

    override bool unregister(int fd)
    {
        if (fd < 0)
        {
            return false;
        }

        return (epoll_ctl(_eventHandle, EPOLL_CTL_DEL, fd, null) == 0);
    }

    override protected void handleEvent()
    {
        epoll_event[64] events;
        const int len = epoll_wait(_eventHandle, events.ptr, events.length, -1);

        foreach (i; 0 .. len)
        {
            auto fd = events[i].data.fd;

            if ((events[i].events & (EPOLLHUP | EPOLLERR | EPOLLRDHUP)) != 0)
            {
                if (fd == _listener.fd)
                {
                    debug writeln("Listener event error.", fd);
                }
                else
                {
                    int err;
                    socklen_t errlen = err.sizeof;
                    getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &errlen);
                    removeClient(fd, err);

                    debug writeln("Close event: ", fd);
                }

                continue;
            }

            if (fd == _listener.fd)
            {
                accept();
            }
            else if (events[i].events & EPOLLIN)
            {
                read(fd);
            }
            else if (events[i].events & EPOLLOUT)
            {
                write(fd);
            }
        }
    }
}
