use anyhow::Result;
use log::{error, info, trace};
use rqs_lib::channel::{ChannelDirection, TransferType};
use std::sync::Arc;
use zbus::connection::Builder;

mod core;
mod dbus;

use crate::core::QuickShareCore;
use crate::dbus::QuickShareDBus;

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));
    info!("Starting DMS Quick Share Daemon");

    // Initialize core and get message receiver
    let (core, mut msg_receiver) = match QuickShareCore::new().await {
        Ok((c, r)) => (c, r),
        Err(e) => {
            error!("Failed to initialize QuickShareCore: {}", e);
            return Err(e);
        }
    };
    
    let core = Arc::new(core);

    let daemon = QuickShareDBus {
        core: Arc::clone(&core),
    };

    let conn = match Builder::session() {
        Ok(builder) => builder,
        Err(e) => {
            error!("Failed to connect to D-Bus session: {}", e);
            return Err(e.into());
        }
    }
    .name("org.danklinux.QuickShare")?
    .serve_at("/org/danklinux/QuickShare", daemon)?
    .build()
    .await?;

    info!("D-Bus interface registered on org.danklinux.QuickShare");
    
    let iface_ref = conn.object_server().interface::<_, QuickShareDBus>("/org/danklinux/QuickShare").await?;
    let signal_context = iface_ref.signal_context().clone().into_owned();

    // Background task to process events from the rqs library
    tokio::spawn(async move {
        while let Ok(msg) = msg_receiver.recv().await {
            if msg.direction == ChannelDirection::LibToFront {
                let is_inbound = msg.rtype == Some(TransferType::Inbound);
                
                let mut total_bytes = 0;
                let mut ack_bytes = 0;
                if let Some(ref meta) = msg.meta {
                    total_bytes = meta.total_bytes;
                    ack_bytes = meta.ack_bytes;
                }
                
                if let Some(state) = msg.state {
                    let state_str = format!("{:?}", state);
                    trace!("Transfer {} state changed: {}", msg.id, state_str);
                    
                    let _ = QuickShareDBus::transfer_progress(&signal_context, &msg.id, &state_str, ack_bytes, total_bytes).await;

                    if is_inbound && state_str == "WaitingForUserConsent" {
                        let device_name = msg.meta.as_ref()
                            .and_then(|m| m.source.as_ref())
                            .and_then(|s| Some(s.name.clone()))
                            .unwrap_or_else(|| "Unknown".to_string());
                            
                        let pin = msg.meta.as_ref()
                            .and_then(|m| m.pin_code.clone())
                            .unwrap_or_else(|| "".to_string());

                        info!("Incoming transfer request from {} (PIN: {})", device_name, pin);
                        let _ = QuickShareDBus::transfer_requested(&signal_context, &msg.id, &device_name, &pin).await;
                    }
                }
            }
        }
    });

    let pending = std::future::pending::<()>();
    pending.await;

    Ok(())
}
