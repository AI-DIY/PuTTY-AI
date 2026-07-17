param(
    [int]$HttpPort = 18080,
    [int]$RawPort = 18022,
    [Parameter(Mandatory = $true)]
    [string]$CapturePath,
    [switch]$Dangerous
)

$source = @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;

public static class PuttyAiMockServices
{
    public static void Run(
        int httpPort, int rawPort, string capturePath, bool dangerous)
    {
        Task http = Task.Run(() => RunHttp(httpPort, dangerous));
        Task raw = Task.Run(() => RunRaw(rawPort, capturePath));
        if (!Task.WaitAll(new[] { http, raw }, TimeSpan.FromSeconds(30)))
            throw new TimeoutException("Mock services timed out");
    }

    private static void RunHttp(int port, bool dangerous)
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        try
        {
            using (TcpClient client = listener.AcceptTcpClient())
            using (NetworkStream stream = client.GetStream())
            using (StreamReader reader = new StreamReader(
                stream, Encoding.UTF8, false, 4096, true))
            {
                int contentLength = 0;
                string line;
                while (!string.IsNullOrEmpty(line = reader.ReadLine()))
                {
                    if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                        int.TryParse(line.Substring(15).Trim(), out contentLength);
                }
                char[] body = new char[contentLength];
                int total = 0;
                while (total < body.Length)
                {
                    int n = reader.Read(body, total, body.Length - total);
                    if (n <= 0) break;
                    total += n;
                }

                string command = dangerous ?
                    "rm -rf /tmp/putty-ai-test" : "echo putty-ai-ok";
                string json =
                    "{\"choices\":[{\"message\":{\"content\":" +
                    "\"## Mock analysis\\nRemote model service is reachable.\\n\\n" +
                    "```bash\\n" + command + "\\n```\"}}]}";
                byte[] payload = Encoding.UTF8.GetBytes(json);
                byte[] headers = Encoding.ASCII.GetBytes(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" +
                    "Content-Length: " + payload.Length +
                    "\r\nConnection: close\r\n\r\n");
                stream.Write(headers, 0, headers.Length);
                stream.Write(payload, 0, payload.Length);
                stream.Flush();
            }
        }
        finally
        {
            listener.Stop();
        }
    }

    private static void RunRaw(int port, string capturePath)
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        try
        {
            using (TcpClient client = listener.AcceptTcpClient())
            using (NetworkStream stream = client.GetStream())
            {
                byte[] greeting = Encoding.UTF8.GetBytes(
                    "PuTTY AI mock remote service ready\r\n$ ");
                stream.Write(greeting, 0, greeting.Length);
                stream.Flush();
                stream.ReadTimeout = 15000;
                byte[] buffer = new byte[8192];
                int count = stream.Read(buffer, 0, buffer.Length);
                byte[] received = new byte[count];
                Buffer.BlockCopy(buffer, 0, received, 0, count);
                File.WriteAllBytes(capturePath, received);
            }
        }
        finally
        {
            listener.Stop();
        }
    }
}
'@

Add-Type -TypeDefinition $source
[PuttyAiMockServices]::Run($HttpPort, $RawPort, $CapturePath, $Dangerous.IsPresent)
