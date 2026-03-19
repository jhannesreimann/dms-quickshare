use anyhow::Result;
use log::{error, info, trace};
use rqs_lib::{
    channel::{ChannelAction, ChannelDirection, ChannelMessage, TransferType},
    EndpointInfo, SendInfo, Visibility, RQS, OutboundPayload,
};
use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, mpsc};
use zbus::{connection::Builder, interface, SignalContext};

// The state our D-Bus interface will manipulate
struct QuickShareDaemon {
    rqs: Arc<Mutex<RQS>>,
    sender_file: mpsc::Sender<SendInfo>,
}

#[interface(name = "org.danklinux.QuickShare")]
impl QuickShareDaemon {
    async fn set_visibility(&self, visible: bool) -> zbus::fdo::Result<()> {
        let visibility = if visible {
            Visibility::Visible
        } else {
            Visibility::Invisible
        };
        
        let rqs = self.rqs.lock().unwrap();
        if let Err(e) = rqs.visibility_sender.lock().unwrap().send(visibility) {
            error!("Failed to change visibility: {}", e);
            return Err(zbus::fdo::Error::Failed("Failed to change visibility".into()));
        }
        
        info!("Visibility changed to: {:?}", visibility);
        Ok(())
    }

    async fn start_discovery(&self, #[zbus(signal_context)] ctxt: SignalContext<'_>) -> zbus::fdo::Result<()> {
        let mut rqs = self.rqs.lock().unwrap();
        
        let (dch_sender, mut dch_receiver) = broadcast::channel::<EndpointInfo>(50);
        
        if let Err(e) = rqs.discovery(dch_sender) {
            error!("Failed to start discovery: {}", e);
            return Err(zbus::fdo::Error::Failed(format!("Failed to start discovery: {}", e)));
        }
        
        let ctxt = ctxt.into_owned();
        tokio::spawn(async move {
            while let Ok(endpoint) = dch_receiver.recv().await {
                let name = endpoint.name.unwrap_or_else(|| "Unknown Device".to_string());
                let ip = endpoint.ip.unwrap_or_else(|| "".to_string());
                info!("Discovered device: {} ({}) at {}", name, endpoint.id, ip);
                if let Err(e) = QuickShareDaemon::device_discovered(&ctxt, &endpoint.id, &name, &ip).await {
                    error!("Failed to emit device_discovered signal: {}", e);
                }
            }
        });
        
        info!("Started discovery for Quick Share devices");
        Ok(())
    }

    async fn send_files(&self, device_id: String, device_name: String, ip_addr: String, files: Vec<String>) -> zbus::fdo::Result<()> {
        info!("Request to send {} files to {}", files.len(), device_name);
        
        let send_info = SendInfo {
            id: device_id,
            name: device_name,
            addr: ip_addr,
            ob: OutboundPayload::Files(files),
        };

        if let Err(e) = self.sender_file.send(send_info).await {
            error!("Failed to queue files for sending: {}", e);
            return Err(zbus::fdo::Error::Failed(format!("Failed to send files: {}", e)));
        }

        Ok(())
    }

    async fn accept_transfer(&self, transfer_id: String) -> zbus::fdo::Result<()> {
        info!("Accepting transfer {}", transfer_id);
        let rqs = self.rqs.lock().unwrap();
        
        let msg = ChannelMessage {
            id: transfer_id,
            direction: ChannelDirection::FrontToLib,
            action: Some(ChannelAction::AcceptTransfer),
            rtype: None,
            state: None,
            meta: None,
        };

        if let Err(e) = rqs.message_sender.send(msg) {
            error!("Failed to accept transfer: {}", e);
            return Err(zbus::fdo::Error::Failed("Failed to send accept message".into()));
        }

        Ok(())
    }

    async fn reject_transfer(&self, transfer_id: String) -> zbus::fdo::Result<()> {
        info!("Rejecting transfer {}", transfer_id);
        let rqs = self.rqs.lock().unwrap();
        
        let msg = ChannelMessage {
            id: transfer_id,
            direction: ChannelDirection::FrontToLib,
            action: Some(ChannelAction::RejectTransfer),
            rtype: None,
            state: None,
            meta: None,
        };

        if let Err(e) = rqs.message_sender.send(msg) {
            error!("Failed to reject transfer: {}", e);
            return Err(zbus::fdo::Error::Failed("Failed to send reject message".into()));
        }

        Ok(())
    }

    #[zbus(signal)]
    async fn device_discovered(ctxt: &SignalContext<'_>, id: &str, name: &str, ip: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn transfer_requested(ctxt: &SignalContext<'_>, id: &str, device_name: &str, pin: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn transfer_progress(ctxt: &SignalContext<'_>, id: &str, state: &str) -> zbus::Result<()>;
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));
    info!("Starting DMS Quick Share Daemon");

    let mut rqs = RQS::new(Visibility::Invisible, None, None);
    
    // The channel we listen on for incoming messages from the lib (like transfer requests)
    let mut msg_receiver = rqs.message_sender.subscribe();
    
    let (sender_file, _ble_receiver) = rqs.run().await?;
    let rqs = Arc::new(Mutex::new(rqs));

    let daemon = QuickShareDaemon {
        rqs: Arc::clone(&rqs),
        sender_file,
    };

    let conn = Builder::session()?
        .name("org.danklinux.QuickShare")?
        .serve_at("/org/danklinux/QuickShare", daemon)?
        .build()
        .await?;

    info!("D-Bus interface registered on org.danklinux.QuickShare");
    
    // Zbus 4.0 uses interface_ref directly from the object server connection
    let iface_ref = conn.object_server().interface::<_, QuickShareDaemon>("/org/danklinux/QuickShare").await?;
    let signal_context = iface_ref.signal_context().clone().into_owned();

    // Background task to process events from the rqs library
    tokio::spawn(async move {
        while let Ok(msg) = msg_receiver.recv().await {
            if msg.direction == ChannelDirection::LibToFront {
                // Determine if it's inbound or outbound
                let is_inbound = msg.rtype == Some(TransferType::Inbound);
                
                if let Some(state) = msg.state {
                    let state_str = format!("{:?}", state);
                    trace!("Transfer {} state changed: {}", msg.id, state_str);
                    
                    let _ = QuickShareDaemon::transfer_progress(&signal_context, &msg.id, &state_str).await;

                    // If it's a new inbound request waiting for acceptance
                    if is_inbound && state_str == "Request" {
                        let device_name = msg.meta.as_ref()
                            .and_then(|m| m.source.as_ref())
                            .and_then(|s| Some(s.name.clone()))
                            .unwrap_or_else(|| "Unknown".to_string());
                            
                        let pin = msg.meta.as_ref()
                            .and_then(|m| m.pin_code.clone())
                            .unwrap_or_else(|| "".to_string());

                        info!("Incoming transfer request from {} (PIN: {})", device_name, pin);
                        let _ = QuickShareDaemon::transfer_requested(&signal_context, &msg.id, &device_name, &pin).await;
                    }
                }
            }
        }
    });

    let pending = std::future::pending::<()>();
    pending.await;

    Ok(())
}
