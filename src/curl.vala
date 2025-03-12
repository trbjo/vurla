namespace CurlClient {
    public errordomain HttpClientError {
        ERROR,
        ERROR_ACCESS,
        ERROR_NO_ENTRY
    }

    public enum HttpClientMethod {
        GET,
        POST,
        DELETE,
    }

    public struct SSEMessage {
        public string? event;
        public string? data;
        public string? id;
        public string? retry;
    }

    public delegate void SSECallback(SSEMessage message);

    public class HttpClient : Object {
        public bool verbose;
        public string? unix_socket_path {get; set;}
        public string? base_url;
        private Curl.SList? headers;

        public HttpClient() {
            verbose = Environment.get_variable("G_MESSAGES_DEBUG") != null;
        }

        public void add_header(string header) {
            headers = Curl.SList.append((owned)headers, header);
        }

        public void add_headers(string[] new_headers) {
            foreach (string header in new_headers) {
                headers = Curl.SList.append((owned)headers, header);
            }
        }

        public void clear_headers() {
            if (headers != null) {
                headers = null;
            }
        }

        private class StreamingData : GLib.Object {
            public SSECallback callback;
            public HttpClient client;
            public GLib.StringBuilder buffer;
            public SSEMessage current_message;

            public StreamingData(HttpClient client, owned SSECallback cb) {
                this.client = client;
                this.callback = (owned)cb;
                this.buffer = new GLib.StringBuilder();
                this.current_message = SSEMessage();
            }

            public void reset_current_message() {
                this.current_message = SSEMessage();
            }
        }

        private static size_t stream_write_function(void* buf, size_t size, size_t nmemb, void* data) {
            size_t real_size = size * nmemb;
            var stream_data = (StreamingData)data;

            uint8[] buffer = new uint8[real_size + 1];
            Posix.memcpy((void*)buffer, buf, real_size);
            buffer[real_size] = 0;

            string text = (string)buffer;
            stream_data.buffer.append(text);

            // Process complete messages (separated by double newline as per SSE spec)
            string accumulated = stream_data.buffer.str;
            string[] messages = accumulated.split("\n\n");

            // Process all complete messages
            for (int i = 0; i < messages.length - 1; i++) {
                string complete_message = messages[i].strip();
                if (complete_message != "") {
                    process_sse_message(complete_message, stream_data);
                }
            }

            // Keep the last (possibly incomplete) message in the buffer
            stream_data.buffer.assign(messages[messages.length - 1]);

            return real_size;
        }

        private static void process_sse_message(string message_text, owned StreamingData stream_data) {
            stream_data.reset_current_message();

            foreach (string line in message_text.split("\n")) {
                string trimmed = line.strip();
                if (trimmed == "") continue;

                if (trimmed.has_prefix("event: ")) {
                    stream_data.current_message.event = trimmed.substring(7);
                } else if (trimmed.has_prefix("data: ")) {
                    stream_data.current_message.data = trimmed.substring(6);
                } else if (trimmed.has_prefix("id: ")) {
                    stream_data.current_message.id = trimmed.substring(4);
                } else if (trimmed.has_prefix("retry: ")) {
                    stream_data.current_message.retry = trimmed.substring(7);
                }
            }

            stream_data.callback(stream_data.current_message);
        }

        public HttpClientResponse request_streaming(
            HttpClientMethod method,
            string url,
            string? post_data,
            owned SSECallback callback
        ) throws HttpClientError {
            var curl = new Curl.EasyHandle();
            var response = new HttpClientResponse();
            var stream_data = new StreamingData(this, (owned)callback);

            Curl.Code r;

            r = curl.setopt(Curl.Option.VERBOSE, this.verbose ? 1 : 0);
            GLib.assert_true(r == Curl.Code.OK);
            r = curl.setopt(Curl.Option.URL, (this.base_url ?? "") + url);
            GLib.assert_true(r == Curl.Code.OK);

            if (unix_socket_path != null) {
                r = curl.setopt(Curl.Option.UNIX_SOCKET_PATH, unix_socket_path);
                GLib.assert_true(r == Curl.Code.OK);
            }

            r = curl.setopt(Curl.Option.CUSTOMREQUEST, this.get_request_method(method));
            GLib.assert_true(r == Curl.Code.OK);

            if (headers != null) {
                r = curl.setopt(Curl.Option.HTTPHEADER, headers);
                GLib.assert_true(r == Curl.Code.OK);
            }

            if (post_data != null && method == HttpClientMethod.POST) {
                r = curl.setopt(Curl.Option.POSTFIELDS, post_data);
                GLib.assert_true(r == Curl.Code.OK);
            }

            r = curl.setopt(Curl.Option.WRITEFUNCTION, stream_write_function);
            GLib.assert_true(r == Curl.Code.OK);
            r = curl.setopt(Curl.Option.WRITEDATA, (void*)stream_data);
            GLib.assert_true(r == Curl.Code.OK);

            r = curl.setopt(Curl.Option.HTTP_TRANSFER_DECODING, 1);
            GLib.assert_true(r == Curl.Code.OK);
            r = curl.setopt(Curl.Option.ACCEPT_ENCODING, "");
            GLib.assert_true(r == Curl.Code.OK);

            r = curl.perform();
            if (r != Curl.Code.OK) {
                throw new HttpClientError.ERROR(Curl.Global.strerror(r));
            }

            long response_code = 0;
            curl.getinfo(Curl.Info.RESPONSE_CODE, &response_code);
            response.code = (int)response_code;

            return response;
        }

        public HttpClientResponse request(
            HttpClientMethod method,
            string? url = null,
            string? post_data = null
        ) throws HttpClientError {
            var curl = new Curl.EasyHandle();
            var response = new HttpClientResponse();

            Curl.Code r;

            r = curl.setopt(Curl.Option.VERBOSE, this.verbose ? 1 : 0);
            GLib.assert_true(r == Curl.Code.OK);
            if (url != null) {
                r = curl.setopt(Curl.Option.URL, url);
            } else {
                r = curl.setopt(Curl.Option.URL, this.base_url);
            }

            GLib.assert_true(r == Curl.Code.OK);

            if (unix_socket_path != null) {
                r = curl.setopt(Curl.Option.UNIX_SOCKET_PATH, unix_socket_path);
                GLib.assert_true(r == Curl.Code.OK);
            }

            r = curl.setopt(Curl.Option.CUSTOMREQUEST, this.get_request_method(method));
            GLib.assert_true(r == Curl.Code.OK);

            if (headers != null) {
                r = curl.setopt(Curl.Option.HTTPHEADER, headers);
                GLib.assert_true(r == Curl.Code.OK);
            }

            if (post_data != null && method == HttpClientMethod.POST) {
                r = curl.setopt(Curl.Option.POSTFIELDS, post_data);
                GLib.assert_true(r == Curl.Code.OK);
            }

            r = curl.setopt(Curl.Option.WRITEDATA, (void*)response);
            GLib.assert_true(r == Curl.Code.OK);
            r = curl.setopt(Curl.Option.WRITEFUNCTION, HttpClientResponse.read_body_data);
            GLib.assert_true(r == Curl.Code.OK);

            r = curl.perform();

            // First check if the curl operation succeeded
            if (r == Curl.Code.OK) {
                long response_code = 0;
                curl.getinfo(Curl.Info.RESPONSE_CODE, &response_code);
                response.code = (int)response_code;
                return response;
            }

            // Only check OS errno if curl operation failed
            long curl_errno = -1;
            curl.getinfo(Curl.Info.OS_ERRNO, &curl_errno);

            if (curl_errno == Posix.ENOENT) {
                throw new HttpClientError.ERROR_NO_ENTRY(strerror((int)curl_errno));
            } else if (curl_errno == Posix.EACCES) {
                throw new HttpClientError.ERROR_ACCESS(strerror((int)curl_errno));
            }

            throw new HttpClientError.ERROR(Curl.Global.strerror(r));
        }

        public string get_request_method(HttpClientMethod method) {
            switch (method) {
                case HttpClientMethod.GET:
                    return "GET";
                case HttpClientMethod.POST:
                    return "POST";
                case HttpClientMethod.DELETE:
                    return "DELETE";
                default:
                    return "";
            }
        }
    }

    public class HttpClientResponse : Object {
        public int code;
        private GLib.MemoryInputStream memory_stream;
        private GLib.DataInputStream body_data_stream;
        private size_t data_length;

        public HttpClientResponse() {
            this.code = 0;
            this.memory_stream = new GLib.MemoryInputStream();
            this.body_data_stream = new GLib.DataInputStream(this.memory_stream);
            this.data_length = 0;
        }

        public static size_t read_body_data(void* buf, size_t size, size_t nmemb, void* data) {
            size_t real_size = size * nmemb;
            uint8[] buffer = new uint8[real_size];
            var response = (HttpClientResponse)data;

            Posix.memcpy((void*)buffer, buf, real_size);
            response.memory_stream.add_data(buffer);
            response.data_length += real_size;

            return real_size;
        }

        public string get_response_body() {
            if (memory_stream != null && data_length > 0) {
                try {
                    memory_stream.seek(0, GLib.SeekType.SET);
                    uint8[] buffer = new uint8[data_length];
                    size_t bytes_read = memory_stream.read(buffer);
                    return (string)buffer[0:bytes_read];
                } catch (GLib.Error e) {
                    GLib.warning("Error reading response body: %s", e.message);
                }
            }
            return "";
        }
    }
}
